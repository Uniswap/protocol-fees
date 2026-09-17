// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {Call, LibCall} from "govkit/types/Call.sol";
import {Proposal} from "govkit/types/Proposal.sol";
import {IUniswapV2Factory} from "govkit/interfaces/IUniswapV2Factory.sol";
import {IUniswapV3Factory} from "govkit/interfaces/IUniswapV3Factory.sol";
import {IPoolManager} from "govkit/interfaces/IPoolManager.sol";
import {WormholeEncoder} from "govkit/bridges/WormholeEncoder.sol";
import {Vm} from "forge-std/Vm.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Currency} from "v4-core/types/Currency.sol";

import {
  IWormhole as IWormholeCore
} from "lib/native-token-transfers/evm/lib/wormhole-solidity-sdk/src/interfaces/IWormhole.sol";
import {
  IWormholeTransceiver
} from "lib/native-token-transfers/evm/src/interfaces/IWormholeTransceiver.sol";

import {ArcFees, buildProposal} from "../../../script/proposal-7/ArcFees.s.sol";
import {DeployFeeInfraArc} from "../../../script/proposal-7/prereq/DeployFeeInfraArc.s.sol";
import {IUniswapWormholeMessageReceiver} from "../../../script/proposal-7/Interfaces.sol";
import "../../../script/proposal-7/params/Constants.sol" as Constants;
import {WormholeDecode} from "../../utils/WormholeDecode.sol";
import {executeAsTimelock} from "../../utils/TimelockExecution.sol";
import {SyntheticNttUni} from "../../../src/wormhole/SyntheticNttUni.sol";
import {WormholeReleaser} from "../../../src/releasers/WormholeReleaser.sol";

/// @dev Arc block the fork is pinned to. Chosen while the receiver held every authority
/// `preflightArc` requires and before any fee infra existed on Arc. Once the live deployment is
/// recorded in `.records/Arc.json`, move this to a block after it; the tests then run against
/// the live contracts instead of deploying their own.
uint256 constant ARC_BLOCK = 21_222_893;

/// @dev Mainnet block the proposal is built at. `buildProposal` reads the Wormhole message fee
/// from the mainnet core, so it needs a mainnet fork selected.
uint256 constant MAINNET_BLOCK = 25_992_796;

/// @dev The Ethereum sender prefixes this version tag to every payload it publishes, and the Arc
/// receiver rejects any payload without it. The sender does not expose it, so we reproduce it
/// here from `messagePayloadVersion` in the sender's verified source,
/// `UniswapWormholeMessageSender.sol`.
bytes32 constant PAYLOAD_VERSION = keccak256(
  abi.encode(
    "UniswapWormholeMessageSenderV1 (bytes32 receivedMessagePayloadVersion, address[] memory targets, uint256[] memory values, bytes[] memory datas, address messageReceiver, uint16 receiverChainId)"
  )
);

address constant BURN_ADDRESS = address(0xdead);

/// @dev The prerequisite script, pointed at the record named at construction.
contract DeployFeeInfraArcHarness is DeployFeeInfraArc {
  string internal recordName;

  constructor(string memory recordName_) {
    // Each test deploys under its own name: forge runs test functions in parallel and `run()`
    // writes the record to disk.
    recordName = recordName_;
  }

  function _recordName() internal view override returns (string memory) {
    return recordName;
  }
}

/// @dev Tests for the Arc half of the proposal, against an Arc fork.
contract ArcFeesArcForkTest is Test {
  Uniswap internal uniswap;
  Recorder internal recorder;

  uint256 internal arcFork;
  uint256 internal mainnetFork;

  function setUp() public {
    arcFork = vm.createSelectFork("arc", ARC_BLOCK);
    mainnetFork = vm.createFork("mainnet", MAINNET_BLOCK);
    uniswap.loadLatest();
  }

  function test_preflightArc() public {
    new ArcFees().preflightArc(ARC_BLOCK);
  }

  /// @dev Asserts the Arc deployment passes the prerequisite script's own checks.
  function test_DeployFeeInfraArc() public {
    // Against the live deployment, `check()` loads the real record and runs `_check` on it.
    if (_liveRecordExists()) {
      new DeployFeeInfraArc().check();
      return;
    }

    // Otherwise deploy. Inside `run()`, `_check` asserts the deployment against the script's own
    // params before `_record` writes it, so a record with every key means the deployment passed
    // its own check.
    _loadArcDeployment(false, "ArcForkDeployTest");

    uint256 chainId = Constants.Arc.CHAIN_ID;
    string[10] memory keys = [
      Constants.Records.SYNTHETIC_NTT_UNI,
      Constants.Records.NTT_MANAGER_IMPLEMENTATION,
      Constants.Records.NTT_MANAGER,
      Constants.Records.WORMHOLE_TRANSCEIVER_IMPLEMENTATION,
      Constants.Records.WORMHOLE_TRANSCEIVER,
      Constants.Records.TOKEN_JAR,
      Constants.Records.RELEASER,
      Constants.Records.V3_OPEN_FEE_ADAPTER,
      Constants.Records.V4_FEE_ADAPTER,
      Constants.Records.V4_FEE_POLICY
    ];
    for (uint256 i; i < keys.length; i++) {
      assertTrue(recorder.exists(chainId, keys[i]), keys[i]);
    }
  }

  /// @dev Delivers the proposal's Arc message through the deployed receiver and asserts it
  /// dispatched exactly the calls decoded from the proposal and flipped the three fee switches.
  function test_receiveMessage() public {
    _loadArcDeployment(_liveRecordExists(), "ArcForkActivateTest");

    uint256 chainId = Constants.Arc.CHAIN_ID;
    address tokenJar = recorder.read(chainId, Constants.Records.TOKEN_JAR);
    address v3OpenFeeAdapter = recorder.read(chainId, Constants.Records.V3_OPEN_FEE_ADAPTER);
    address v4FeeAdapter = recorder.read(chainId, Constants.Records.V4_FEE_ADAPTER);

    // Get the decoded Arc message from the proposal
    (address remoteReceiver, uint16 wormholeChainId, Call[] memory remoteCalls) = _arcMessage();

    // Assert the receiver dispatches exactly the calls the decoder produced from the proposal.
    for (uint256 i; i < remoteCalls.length; i++) {
      vm.expectCall(remoteCalls[i].target, remoteCalls[i].value, remoteCalls[i].data);
    }
    _receiveGovernanceMessage(remoteReceiver, wormholeChainId, remoteCalls);

    // Assert that the three fee switches are flipped.
    assertEq(IUniswapV2Factory(Constants.Arc.V2_FACTORY).feeTo(), tokenJar, "v2Factory.feeTo");
    assertEq(
      IUniswapV3Factory(Constants.Arc.V3_FACTORY).owner(), v3OpenFeeAdapter, "v3Factory.owner"
    );
    assertEq(
      IPoolManager(Constants.Arc.POOL_MANAGER).protocolFeeController(),
      v4FeeAdapter,
      "poolManager.protocolFeeController"
    );
  }

  /// @dev Burns synthetic UNI on Arc through the releaser and delivers the resulting NTT message
  /// to Ethereum, asserting UNI unlocks to the burn address once the proposal has registered the
  /// Arc peers, and not before.
  function test_burnOnArcReleasesOnEthereum() public {
    _loadArcDeployment(_liveRecordExists(), "ArcForkBurnTest");

    uint256 chainId = Constants.Arc.CHAIN_ID;
    // Get the deployed contracts from the test record.
    SyntheticNttUni syntheticUni =
      SyntheticNttUni(recorder.read(chainId, Constants.Records.SYNTHETIC_NTT_UNI));
    address arcNttManager = recorder.read(chainId, Constants.Records.NTT_MANAGER);
    address arcTransceiver = recorder.read(chainId, Constants.Records.WORMHOLE_TRANSCEIVER);
    WormholeReleaser releaser =
      WormholeReleaser(payable(recorder.read(chainId, Constants.Records.RELEASER)));

    // Fund this contract with release threshold amount of synthetic UNI.
    uint256 threshold = releaser.threshold();
    uint256 supplyBefore = syntheticUni.totalSupply();
    vm.prank(arcNttManager);
    syntheticUni.mint(address(this), threshold);
    syntheticUni.approve(address(releaser), threshold);

    // Release with no assets and record the associated event logs from the subsequent releaser
    // and tranceiver calls.
    vm.recordLogs();
    releaser.release(releaser.nonce(), new Currency[](0), address(this));
    Vm.Log[] memory logs = vm.getRecordedLogs();
    // From the logs, extract the payload the Arc transceiver published to the Wormhole core
    bytes memory payload = _getPublishedPayload(logs, Constants.Arc.WORMHOLE_CORE, arcTransceiver);
    // Assert the release burned everything it was given.
    assertEq(syntheticUni.totalSupply(), supplyBefore, "syntheticUni.totalSupply");

    // Get the unlocked amount, trimmed to NTT's eight decimal places
    uint256 unlocked = releaser.wormholeTrim(threshold);

    // We now move to the Ethereum fork to queue the proposal and deliver the message from Arc.
    vm.selectFork(mainnetFork);
    // Set up the proposal
    Proposal memory proposal = buildProposal(uniswap, recorder);
    ERC20 uni = ERC20(uniswap.ethereum.uni);

    // Try delivering before the proposal executes. We expect the NTT message to revert since the
    // Ethereum tranceiver isn't yet peered with the Arc transceiver.
    vm.expectRevert(
      abi.encodeWithSelector(
        IWormholeTransceiver.InvalidWormholePeer.selector,
        Constants.Arc.WORMHOLE_CHAIN_ID,
        WormholeEncoder.toWormholeFormat(arcTransceiver)
      )
    );
    _receiveNttMessage(arcTransceiver, payload);

    // Execute the proposal as the Timelock. Actions 00 and 01 register the Arc transceiver and
    // manager as peers.
    executeAsTimelock(vm, uniswap.ethereum.timelock, proposal.calls);

    // Try delivering again now that the proposal has executed.
    uint256 burnBefore = uni.balanceOf(BURN_ADDRESS);
    uint256 managerBefore = uni.balanceOf(uniswap.ethereum.nttManager);
    _receiveNttMessage(arcTransceiver, payload);

    // Since the tranceiver and NTT manager are now peered with their Arc counterparts, the NTT
    // message should have unlocked the synthetic UNI to the burn address.
    assertEq(uni.balanceOf(BURN_ADDRESS) - burnBefore, unlocked, "uni.burnAddress");
    assertEq(managerBefore - uni.balanceOf(uniswap.ethereum.nttManager), unlocked, "uni.nttManager");
  }

  // -- helpers ----------------------------------------------------------------------------------

  /// @dev Whether the prerequisite script has recorded the live Arc deployment.
  function _liveRecordExists() internal view returns (bool) {
    // Checked with `vm.exists` rather than through the recorder, whose `initialize` would create
    // an empty real record if none existed.
    return vm.exists(string.concat(".records/", Constants.RECORD_NAME, ".json"));
  }

  /// @dev Points `recorder` at the live Arc deployment if `isLive`, else runs the prerequisite
  /// script on the fork under `testRecordName` and points `recorder` at that.
  function _loadArcDeployment(bool isLive, string memory testRecordName) internal {
    if (isLive) {
      recorder.initialize({scriptName: Constants.RECORD_NAME});
      // The fee switches only store addresses, so a test could pass against a record whose
      // contracts do not exist yet at the pinned block. Fail here instead, naming the cause.
      address tokenJar = recorder.read(Constants.Arc.CHAIN_ID, Constants.Records.TOKEN_JAR);
      require(tokenJar.code.length != 0, "ARC_BLOCK predates the live deployment");
      return;
    }

    // Remove any record an earlier run left, or `run()` refuses to deploy over it. The name is
    // specific to the test and distinct from the real record.
    string memory recordPath = string.concat(".records/", testRecordName, ".json");
    if (vm.exists(recordPath)) vm.removeFile(recordPath);

    new DeployFeeInfraArcHarness(testRecordName).run();

    // `run()` initialized the harness's own recorder, a different storage struct in a different
    // contract. This one is the test's handle on the same file: `read` and `buildProposal`
    // require it initialized. Initializing it does not touch a file that already exists.
    recorder.initialize({scriptName: testRecordName});
  }

  /// @dev Builds the proposal from the record and returns the Arc message it carries, decoded.
  function _arcMessage()
    internal
    returns (address remoteReceiver, uint16 wormholeChainId, Call[] memory remoteCalls)
  {
    // Build on the mainnet fork, the way `run()` on Ethereum does: `buildProposal` reads the
    // message fee from the mainnet core.
    vm.selectFork(mainnetFork);
    Proposal memory proposal = buildProposal(uniswap, recorder);
    vm.selectFork(arcFork);

    // Get the Arc message (Action 02) from the proposal and decode it.
    address sourceSender;
    (sourceSender, remoteReceiver, wormholeChainId,, remoteCalls) =
      WormholeDecode.decode(proposal.calls[2]);

    // Assert the envelope is correct.
    assertEq(sourceSender, Constants.Ethereum.WORMHOLE_SENDER, "sourceSender");
    assertEq(remoteReceiver, Constants.Arc.WORMHOLE_RECEIVER, "remoteReceiver");
    assertEq(wormholeChainId, Constants.Arc.WORMHOLE_CHAIN_ID, "wormholeChainId");
  }

  /// @dev Delivers a governance message carrying `remoteCalls` to the deployed Arc receiver, as
  ///      the Ethereum sender would send it. Mocks the Arc core's guardian verification.
  function _receiveGovernanceMessage(
    address remoteReceiver,
    uint16 wormholeChainId,
    Call[] memory remoteCalls
  ) internal {
    // Encode the payload the way the Ethereum sender does.
    (address[] memory targets, uint256[] memory values, bytes[] memory datas) =
      LibCall.decompose(remoteCalls);
    bytes memory payload =
      abi.encode(PAYLOAD_VERSION, targets, values, datas, remoteReceiver, wormholeChainId);

    // Present it as published from Ethereum by the peered sender.
    _mockVerifiedVaa(Constants.Arc.WORMHOLE_CORE, 2, Constants.Ethereum.WORMHOLE_SENDER, payload);

    // Have the receiver pull the message from Core, ie by calling `IWormholeCore.parseAndVerifyVM`.
    // Since we've just mocked that call, we can pass arbitrary bytes to get the return value
    // needed for the test.
    IUniswapWormholeMessageReceiver(remoteReceiver).receiveMessage(new bytes(0));
  }

  /// @dev Delivers an NTT transfer to the Ethereum transceiver, as published on Arc by
  ///      `arcTransceiver`. Mocks the Ethereum core's guardian verification.
  function _receiveNttMessage(address arcTransceiver, bytes memory payload) internal {
    // Present it as published from Arc by the transceiver the proposal registers as the peer.
    _mockVerifiedVaa(
      uniswap.ethereum.bridge.wormholeCore, Constants.Arc.WORMHOLE_CHAIN_ID, arcTransceiver, payload
    );

    // Have the transceiver pull the message from Core, ie by calling
    // `IWormholeCore.parseAndVerifyVM`. Since we've just mocked that call, we can pass arbitrary
    // bytes to get the return value needed for the test.
    IWormholeTransceiver(uniswap.ethereum.wormholeTransceiver).receiveMessage(new bytes(0));
  }

  /// @dev Installs a mock on the Wormhole core at `core` so `parseAndVerifyVM` returns a verified
  /// VAA from `emitter` on `emitterChainId` carrying `payload`.
  function _mockVerifiedVaa(
    address core,
    uint16 emitterChainId,
    address emitter,
    bytes memory payload
  ) internal {
    IWormholeCore.VM memory vaa;
    vaa.version = 1;
    // "Now" is inside the Uniswap receiver's validity window.
    vaa.timestamp = uint32(block.timestamp);
    vaa.emitterChainId = emitterChainId;
    vaa.emitterAddress = WormholeEncoder.toWormholeFormat(emitter);
    vaa.payload = payload;
    // The NTT transceiver records this hash against replay, so it must be unique per payload.
    vaa.hash = keccak256(payload);
    // Sequence stays 0: the deployed Uniswap receiver has processed no message at the pinned
    // block, so 0 passes its monotonic-sequence check.

    // A fork cannot produce guardian signatures, so we mock the core's verification to return
    // this VAA as verified. Every check the caller makes after that call runs on its real
    // bytecode.
    vm.mockCall(
      core,
      abi.encodeWithSelector(IWormholeCore.parseAndVerifyVM.selector),
      abi.encode(vaa, true, "")
    );
  }

  /// @dev Returns the payload of the one message in `logs` that `sender` published through the
  /// Wormhole core at `core`.
  function _getPublishedPayload(Vm.Log[] memory logs, address core, address sender)
    internal
    pure
    returns (bytes memory payload)
  {
    // We're looking for `payload`, the third non-indexed field in this event.
    // event LogMessagePublished(
    //    address indexed sender,
    //    uint64 sequence,
    //    uint32 nonce,
    //    bytes payload,
    //    uint8 consistencyLevel
    // );
    bytes32 topic = IWormholeCore.LogMessagePublished.selector;

    uint256 found;
    for (uint256 i; i < logs.length; i++) {
      // The core emits the event.
      if (logs[i].emitter != core || logs[i].topics[0] != topic) continue;
      // The `sender` (indexed) is the contract that called `publishMessage`, which Wormhole then
      // names as the VAA's emitter. An indexed address is left-padded to the 32-byte topic.
      if (logs[i].topics[1] != bytes32(uint256(uint160(sender)))) continue;
      // Get the payload from the third non-indexed field.
      (,, payload,) = abi.decode(logs[i].data, (uint64, uint32, bytes, uint8));
      found++;
    }
    // There should be exactly one such event.
    assertEq(found, 1, "LogMessagePublished.count");
  }
}
