// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {Call, LibCall} from "govkit/types/Call.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {ITokenJar} from "govkit/interfaces/ITokenJar.sol";
import {IReleaser} from "govkit/interfaces/IReleaser.sol";
import {IL1CrossDomainMessenger} from "govkit/interfaces/bridges/IL1CrossDomainMessenger.sol";
import {IOptimismPortal2} from "govkit/interfaces/bridges/IOptimismPortal2.sol";
import {Predeploys} from "@eth-optimism-bedrock/src/libraries/Predeploys.sol";
import {AddressAliasHelper} from "@eth-optimism-bedrock/src/vendor/AddressAliasHelper.sol";

import {
  ReplaceXLayerReleaser,
  buildReplaceReleaserCall,
  buildStartDecayCall,
  readNewReleaser,
  readThresholdSetter
} from "../../../../script/proposal-103/x-layer/ReplaceXLayerReleaser.s.sol";
import {
  DeployXLayerReleaser
} from "../../../../script/proposal-103/x-layer/prereq/DeployXLayerReleaser.s.sol";
import {RECORD_NAME, Records, XLayer} from "../../../../script/proposal-103/x-layer/Constants.sol";
import {IXLayerBridge} from "../../../../src/interfaces/external/IXLayerBridge.sol";
import {IDecayingThresholdSetter} from "../../../../src/interfaces/IDecayingThresholdSetter.sol";
import {IXLayerBridgeFull} from "../../../interfaces/IXLayerBridgeFull.sol";
import {IGlobalExitRootManagerL1} from "../../../interfaces/IGlobalExitRootManagerL1.sol";
import {IGlobalExitRootManagerL2} from "../../../interfaces/IGlobalExitRootManagerL2.sol";
import {IRollupManager} from "../../../interfaces/IRollupManager.sol";
import {executeAsTimelock} from "../../../utils/TimelockExecution.sol";
import {
  ETHEREUM_NETWORK_ID,
  ETHEREUM_TOKEN_BRIDGE,
  ExitLeaf,
  GLOBAL_INDEX_MAINNET_FLAG,
  UniClaim,
  UniDeposit,
  XLAYER_NETWORK_ID,
  XLAYER_ROLLUP_INDEX,
  ethereumExitRootManager,
  globalExitRoot,
  merkleRootAndProof,
  nextExitLeaf,
  uniMetadata,
  xLayerExitRootManager
} from "../../../utils/XLayerBridging.sol";

/// @dev X Layer block the fork is pinned to. Chosen while the TokenJar still had the old releaser,
/// which `preflightXLayer` requires; the tests stay green at this block after the message relays.
uint256 constant XLAYER_BLOCK = 72_186_640;

/// @dev Mainnet block the proposal executes at. Any block where X Layer's L1CrossDomainMessenger
/// is live and unpaused works.
uint256 constant MAINNET_BLOCK = 26_105_508;

/// @dev The X Layer v2 USDT/WOKB pair. The TokenJar holds its LP token as v2 fees at
/// `XLAYER_BLOCK`; the release test releases it.
address constant USDT_WOKB_V2_PAIR = 0xD5da3993f982C13190139b6f45E6e8023C15515D;

/// @dev The Ethereum address the new releaser sends UNI to, where no one can spend it.
address constant BURN_ADDRESS = address(0xdead);

/// @dev A call X Layer makes to {L2CrossDomainMessenger-relayMessage} to relay one of the
/// proposal's messages, as a {TransactionDeposited} event from X Layer's OptimismPortal records it.
struct RelayMessageCall {
  address from;
  address to;
  uint256 value;
  uint64 gasLimit;
  bytes data;
}

/// @dev The prerequisite script, pointed at the specified record.
contract DeployXLayerReleaserHarness is DeployXLayerReleaser {
  string internal recordName;

  constructor(string memory recordName_) {
    recordName = recordName_;
  }

  function _recordName() internal view override returns (string memory) {
    return recordName;
  }
}

/// @dev The proposal script, pointed at the specified record.
contract ReplaceXLayerReleaserHarness is ReplaceXLayerReleaser {
  string internal recordName;

  constructor(string memory recordName_) {
    recordName = recordName_;
  }

  function _recordName() internal view override returns (string memory) {
    return recordName;
  }
}

/// @dev Tests for the X Layer side of the proposal, against an X Layer fork.
contract ReplaceXLayerReleaserXLayerForkTest is Test {
  Uniswap internal uniswap;
  Recorder internal recorder;

  uint256 internal xLayerFork;
  uint256 internal mainnetFork;

  function setUp() public {
    bool shouldRun = vm.envOr("SHOULD_FORK_TEST", false);
    vm.skip(!shouldRun);

    xLayerFork = vm.createSelectFork("xlayer", XLAYER_BLOCK);
    mainnetFork = vm.createFork("mainnet", MAINNET_BLOCK);
    uniswap.loadLatest();
  }

  function test_preflightXLayer() public {
    string memory recordName = _loadNewReleaser("XLayerForkPreflightTest");
    new ReplaceXLayerReleaserHarness(recordName).preflightXLayer(XLAYER_BLOCK);
  }

  /// @dev Executes the proposal on Ethereum, then makes the two calls that relay its messages on X
  /// Layer. Asserts the TokenJar accepts releases from the new releaser and refuses them from the
  /// old one, and the {DecayingThresholdSetter} started its decay at `XLayer.START_THRESHOLD`.
  function test_relayMessage() public {
    string memory recordName = _loadNewReleaser("XLayerForkRelayTest");
    address newReleaser = readNewReleaser(recorder);
    address thresholdSetter = readThresholdSetter(recorder);
    ITokenJar tokenJar = ITokenJar(uniswap.xLayer.tokenJar);
    address oldReleaser = uniswap.xLayer.releaser;

    // Assert the TokenJar authorizes the old releaser's address before the message lands, to
    // isolate the below revert.
    vm.prank(oldReleaser);
    tokenJar.release(new address[](0), address(this));

    // Execute the proposal on Ethereum and relay its messages on X Layer.
    // {_executeProposalAndRelay} asserts the proposal sent two messages and that no relay call
    // reverts.
    _executeProposalAndRelay();

    // Assert the TokenJar releases through the new releaser and the decay has started.
    new ReplaceXLayerReleaserHarness(recordName).postflightXLayer();

    // Assert {DecayingThresholdSetter-start} started the decay and took the threshold-setter role,
    // and the threshold is `XLayer.START_THRESHOLD`.
    assertEq(
      IDecayingThresholdSetter(thresholdSetter).startTime(), block.timestamp, "setter.startTime"
    );
    assertEq(IReleaser(newReleaser).thresholdSetter(), thresholdSetter, "releaser.thresholdSetter");
    assertEq(IReleaser(newReleaser).threshold(), XLayer.START_THRESHOLD, "releaser.threshold");

    // Assert the TokenJar refuses the old releaser's address and accepts the new releaser's.
    // `test_release` covers a full release through the new releaser.
    vm.expectRevert(ITokenJar.Unauthorized.selector);
    vm.prank(oldReleaser);
    tokenJar.release(new address[](0), address(this));

    vm.prank(newReleaser);
    tokenJar.release(new address[](0), address(this));
  }

  /// @dev Asserts the release flow once the proposal executes and the threshold decays for two
  /// half-lives:
  ///
  /// - A searcher writes the decayed threshold with {DecayingThresholdSetter-poke}.
  /// - The searcher bridges that much UNI from Ethereum to X Layer.
  /// - The searcher pays it into a release of a TokenJar fee asset and receives the fee asset.
  /// - The paid UNI reaches the Ethereum burn address.
  ///
  /// Two is an arbitrary whole number of half-lives. After a whole number `n` of half-lives the
  /// threshold is exactly `XLayer.START_THRESHOLD >> n` while it stays above
  /// `XLayer.FLOOR_THRESHOLD`, so the test can assert its exact value.
  ///
  /// The test makes the calls of X Layer's global exit root updater and Ethereum's RollupManager
  /// itself. It does not cover finality, or the generation and verification of X Layer's
  /// certificates.
  function test_release() public {
    // Assert X Layer is in the state the proposal assumes, including a deployed and handed-over
    // new releaser.
    string memory recordName = _loadNewReleaser("XLayerForkReleaseTest");
    new ReplaceXLayerReleaserHarness(recordName).preflightXLayer(XLAYER_BLOCK);

    _executeProposalAndRelay();

    IReleaser releaser = IReleaser(readNewReleaser(recorder));
    IERC20 uni = IERC20(XLayer.RESOURCE);
    IERC20 feeAsset = IERC20(USDT_WOKB_V2_PAIR);
    address tokenJar = uniswap.xLayer.tokenJar;
    address searcher = makeAddr("searcher");

    // Let the threshold decay for two half-lives, to a quarter of the start threshold, and have the
    // searcher write it to the releaser.
    vm.warp(block.timestamp + 2 * XLayer.HALF_LIFE);
    vm.prank(searcher);
    uint256 threshold = IDecayingThresholdSetter(readThresholdSetter(recorder)).poke();
    assertEq(threshold, XLayer.START_THRESHOLD / 4, "poke");
    assertEq(releaser.threshold(), threshold, "releaser.threshold");

    // Have the searcher bridge the threshold in UNI from Ethereum to X Layer, and approve the
    // releaser to take it.
    _bridgeUniToXLayer(searcher, threshold);
    vm.prank(searcher);
    uni.approve(address(releaser), threshold);

    // Assert the TokenJar holds the fee asset, so the payout assertions below witness a transfer.
    uint256 feeAssetInJar = feeAsset.balanceOf(tokenJar);
    assertGt(feeAssetInJar, 0, "feeAsset.tokenJar.before");
    uint256 uniSupplyBefore = uni.totalSupply();

    address[] memory assets = new address[](1);
    assets[0] = address(feeAsset);
    uint256 nonce = releaser.nonce();

    // Build the proof of the leaf the release will append to X Layer's local exit tree, which the
    // claim on Ethereum needs.
    ExitLeaf memory burnLeaf = nextExitLeaf(XLayer.TOKEN_BRIDGE);

    // Assert the release deposits the threshold in the bridge, to reach the Ethereum burn address
    // as Ethereum UNI. The bridge encodes the wrapped token's metadata into the deposit.
    vm.expectEmit(XLayer.TOKEN_BRIDGE);
    emit IXLayerBridge.BridgeEvent(
      0,
      ETHEREUM_NETWORK_ID,
      uniswap.ethereum.uni,
      ETHEREUM_NETWORK_ID,
      BURN_ADDRESS,
      threshold,
      uniMetadata(),
      burnLeaf.index
    );
    vm.prank(searcher);
    releaser.release(nonce, assets, searcher);

    // Assert the TokenJar released its whole balance of the fee asset to the searcher.
    assertEq(feeAsset.balanceOf(searcher), feeAssetInJar, "feeAsset.searcher");
    assertEq(feeAsset.balanceOf(tokenJar), 0, "feeAsset.tokenJar");

    // Assert the releaser took the threshold UNI but didn't keep it.
    assertEq(uni.balanceOf(searcher), 0, "uni.searcher");
    assertEq(uni.balanceOf(address(releaser)), 0, "uni.releaser");

    // Assert the UNI's supply on X Layer fell by the threshold.
    assertEq(uniSupplyBefore - uni.totalSupply(), threshold, "uni.totalSupply");

    // Assert the release published the bridge's new local exit root to X Layer's global exit root
    // manager, as the releaser requests with `forceUpdateGlobalExitRoot`.
    assertEq(
      xLayerExitRootManager(XLayer.TOKEN_BRIDGE).lastRollupExitRoot(),
      IXLayerBridgeFull(XLayer.TOKEN_BRIDGE).getRoot(),
      "xLayer.lastRollupExitRoot"
    );

    // Settle X Layer's exit root on Ethereum and claim the release's deposit there, asserting the
    // Ethereum bridge pays the threshold to the burn address.
    _claimBurnOnEthereum(burnLeaf, threshold);
  }

  // -- helpers ----------------------------------------------------------------------------------

  /// @dev Points `recorder` at the live deployment if `.records/XLayer.json` holds the new
  /// releaser, else runs the prerequisite script on the fork under `testRecordName` and points
  /// `recorder` at that.
  /// Returns the record name, for the proposal script's harness. Leaves the X Layer fork selected.
  function _loadNewReleaser(string memory testRecordName) internal returns (string memory) {
    vm.selectFork(xLayerFork);

    // A dry run of the prerequisite script, or a preflight before deployment, leaves an empty
    // real record, so we check for the releaser's key rather than for the file.
    if (_releaserRecorded(RECORD_NAME)) {
      recorder.initialize({scriptName: RECORD_NAME});
      // Fail here, naming the cause, if the record's releaser does not exist at the pinned block.
      require(readNewReleaser(recorder).code.length != 0, "XLAYER_BLOCK predates the deployment");
      return RECORD_NAME;
    }

    _clearRecord(testRecordName);
    new DeployXLayerReleaserHarness(testRecordName).run();

    // `run()` initialized the harness's own recorder. This one is the test's handle on the same
    // file. The proposal builders and readers assume it is initialized.
    recorder.initialize({scriptName: testRecordName});
    return testRecordName;
  }

  /// @dev Returns whether the record named `recordName` holds the new releaser's address. Reads the
  /// file directly, since the recorder's `initialize` creates an empty record where none exists.
  function _releaserRecorded(string memory recordName) internal view returns (bool) {
    string memory recordPath = string.concat(".records/", recordName, ".json");
    if (!vm.exists(recordPath)) return false;
    return vm.keyExistsJson(
      vm.readFile(recordPath),
      string.concat(".", vm.toString(ChainId.XLayer), ".", Records.RELEASER)
    );
  }

  /// @dev Removes the test record `recordName` an earlier run left, or the prerequisite script
  /// refuses to deploy over it. Forge runs test functions in parallel, so each test uses its own
  /// name, gitignored as `.records/*Test.json`.
  function _clearRecord(string memory recordName) internal {
    string memory recordPath = string.concat(".records/", recordName, ".json");
    if (vm.exists(recordPath)) vm.removeFile(recordPath);
  }

  /// @dev Executes the proposal's two X Layer calls on Ethereum, then makes the calls that relay
  /// their messages on X Layer, in order. Asserts the calls sent exactly two messages and that no
  /// relay call reverts. Assumes `recorder` is initialized. Leaves the X Layer fork selected.
  function _executeProposalAndRelay() internal {
    vm.selectFork(mainnetFork);
    Call[] memory calls = LibCall.newCalls(
      [buildReplaceReleaserCall(uniswap, recorder), buildStartDecayCall(uniswap, recorder)]
    );
    address portal = IL1CrossDomainMessenger(uniswap.ethereum.bridge.xLayer).PORTAL();

    vm.recordLogs();
    executeAsTimelock(vm, uniswap.ethereum.timelock, calls);
    RelayMessageCall[] memory relayCalls = _relayMessageCallsFromLogs(vm.getRecordedLogs(), portal);

    // Assert the calls sent two messages. The relay calls follow log order, which is proposal
    // order.
    assertEq(relayCalls.length, 2, "TransactionDeposited.count");

    vm.selectFork(xLayerFork);

    // Make each relay call with the gas its execution gets on X Layer: the call's gas limit less
    // the transaction's intrinsic gas. If a message's gas limit is too low, the
    // L2CrossDomainMessenger records the message as failed instead of reverting, and the
    // postflight check catches it.
    for (uint256 i; i < relayCalls.length; i++) {
      RelayMessageCall memory relayCall = relayCalls[i];
      vm.prank(relayCall.from);
      (bool success,) = relayCall.to
      .call{value: relayCall.value, gas: relayCall.gasLimit - _intrinsicGas(relayCall.data)}(
        relayCall.data
      );
      require(success, "relay call reverted");
    }
  }

  /// @dev Returns, in log order, the relay calls that `portal`, X Layer's OptimismPortal, recorded
  /// in `logs` for messages from X Layer's L1CrossDomainMessenger to the L2CrossDomainMessenger.
  function _relayMessageCallsFromLogs(Vm.Log[] memory logs, address portal)
    internal
    view
    returns (RelayMessageCall[] memory relayCalls)
  {
    uint256 count;
    for (uint256 i; i < logs.length; i++) {
      if (_isRelayedMessage(logs[i], portal)) count++;
    }

    relayCalls = new RelayMessageCall[](count);
    uint256 next;
    for (uint256 i; i < logs.length; i++) {
      if (!_isRelayedMessage(logs[i], portal)) continue;
      // Assert the event is version 0, the `opaqueData` layout {decodeOpaqueData} reads.
      assertEq(uint256(logs[i].topics[3]), 0, "TransactionDeposited.version");
      RelayMessageCall memory relayCall = relayCalls[next++];
      relayCall.from = AddressAliasHelper.applyL1ToL2Alias(uniswap.ethereum.bridge.xLayer);
      relayCall.to = Predeploys.L2_CROSS_DOMAIN_MESSENGER;
      (relayCall.value, relayCall.gasLimit, relayCall.data) =
        this.decodeOpaqueData(abi.decode(logs[i].data, (bytes)));
    }
  }

  /// @dev Returns whether `portal`, X Layer's OptimismPortal, emitted `log` as a
  /// {TransactionDeposited} for a message from X Layer's L1CrossDomainMessenger to the
  /// L2CrossDomainMessenger.
  function _isRelayedMessage(Vm.Log memory log, address portal) internal view returns (bool) {
    // event TransactionDeposited(
    //    address indexed from,
    //    address indexed to,
    //    uint256 indexed version,
    //    bytes opaqueData
    // );
    //
    // The portal names the L1 messenger by its aliased address, which is the relay call's sender
    // on X Layer.
    address from = AddressAliasHelper.applyL1ToL2Alias(uniswap.ethereum.bridge.xLayer);
    return log.emitter == portal && log.topics[0] == IOptimismPortal2.TransactionDeposited.selector
      && log.topics[1] == bytes32(uint256(uint160(from)))
      && log.topics[2] == bytes32(uint256(uint160(Predeploys.L2_CROSS_DOMAIN_MESSENGER)));
  }

  /// @dev Decodes the `opaqueData` of a version 0 {TransactionDeposited} event into the fields of
  /// the relay call it records. External so it can slice calldata.
  ///
  /// The Optimism contracts have no Solidity decoder for `opaqueData`, so we write one here. The
  /// layout is `mint` (32 bytes), `value` (32 bytes), `gasLimit` (8 bytes), `isCreation` (1 byte),
  /// then `data`. Two sources, both in `lib/optimism`, confirm it:
  ///
  /// - The encoder: `OptimismPortal2.depositTransaction` packs it as
  ///   `abi.encodePacked(msg.value, _value, _gasLimit, _isCreation, _data)`, in
  ///   `packages/contracts-bedrock/src/L1/OptimismPortal2.sol`.
  /// - The decoder: the OP Stack node builds the relay call from the same layout in
  ///   `unmarshalDepositVersion0`, in `op-node/rollup/derive/deposit_log.go`.
  function decodeOpaqueData(bytes calldata opaqueData)
    external
    pure
    returns (uint256 value, uint64 gasLimit, bytes memory data)
  {
    value = uint256(bytes32(opaqueData[32:64]));
    gasLimit = uint64(bytes8(opaqueData[64:72]));
    data = opaqueData[73:];
  }

  /// @dev Returns the intrinsic gas of a transaction carrying `data`: 21,000, plus 4 per zero byte
  /// and 16 per non-zero byte of calldata, as set out in the Ethereum Yellow Paper's Appendix G and
  /// EIP-2028.
  ///
  /// We subtract it because we assume X Layer charges relay calls intrinsic gas like any other
  /// transaction. If it does not, execution gets more gas than we give it, so the test errs
  /// strict.
  function _intrinsicGas(bytes memory data) internal pure returns (uint256 gas) {
    gas = 21_000;
    for (uint256 i; i < data.length; i++) {
      gas += data[i] == 0 ? 4 : 16;
    }
  }

  /// @dev Has `to` deposit `amount` of UNI in the unified bridge on Ethereum, addressed to itself
  /// on X Layer, then claims the deposit on X Layer. Asserts the Ethereum bridge escrows the UNI
  /// and the X Layer bridge mints `amount` of `XLayer.RESOURCE` to `to`. Leaves the X Layer fork
  /// selected.
  function _bridgeUniToXLayer(address to, uint256 amount) internal {
    vm.selectFork(mainnetFork);
    UniDeposit memory deposit = _depositUniOnEthereum(to, amount);
    vm.selectFork(xLayerFork);
    _claimUniOnXLayer(deposit);
  }

  /// @dev Has `to` deposit `amount` of UNI in the unified bridge on Ethereum, addressed to itself
  /// on X Layer, and returns what a claim of the deposit needs. Asserts the bridge escrows the UNI
  /// and pushes its new exit root to the global exit root manager. Runs on the selected fork, which
  /// must be the Ethereum fork.
  function _depositUniOnEthereum(address to, uint256 amount)
    internal
    returns (UniDeposit memory deposit)
  {
    IXLayerBridgeFull bridge = IXLayerBridgeFull(ETHEREUM_TOKEN_BRIDGE);
    IERC20 uni = IERC20(uniswap.ethereum.uni);
    deposit.recipient = to;
    deposit.amount = amount;
    deposit.leaf = nextExitLeaf(ETHEREUM_TOKEN_BRIDGE);

    // Have `to` deposit `amount` of UNI for itself on X Layer, asserting the bridge appends a leaf
    // at the index the proof is for.
    uint256 escrowedBefore = uni.balanceOf(ETHEREUM_TOKEN_BRIDGE);
    deal(address(uni), to, amount);
    vm.startPrank(to);
    uni.approve(ETHEREUM_TOKEN_BRIDGE, amount);
    vm.expectEmit(ETHEREUM_TOKEN_BRIDGE);
    emit IXLayerBridge.BridgeEvent(
      0,
      ETHEREUM_NETWORK_ID,
      address(uni),
      XLAYER_NETWORK_ID,
      to,
      amount,
      uniMetadata(),
      deposit.leaf.index
    );
    bridge.bridgeAsset(XLAYER_NETWORK_ID, to, amount, address(uni), true, "");
    vm.stopPrank();

    // Assert the bridge escrowed the UNI.
    assertEq(uni.balanceOf(ETHEREUM_TOKEN_BRIDGE) - escrowedBefore, amount, "uni.ethereumBridge");

    deposit.mainnetExitRoot =
      _assertUniExitLeaf(ETHEREUM_TOKEN_BRIDGE, deposit.leaf, XLAYER_NETWORK_ID, to, amount);

    // Assert the deposit pushed the bridge's new exit root to the global exit root manager, and the
    // manager recorded the resulting global exit root. X Layer's updater relays only a global exit
    // root Ethereum has recorded.
    IGlobalExitRootManagerL1 manager = IGlobalExitRootManagerL1(bridge.globalExitRootManager());
    assertEq(manager.lastMainnetExitRoot(), deposit.mainnetExitRoot, "lastMainnetExitRoot");
    deposit.rollupExitRoot = manager.lastRollupExitRoot();
    assertNotEq(
      manager.globalExitRootMap(globalExitRoot(deposit.mainnetExitRoot, deposit.rollupExitRoot)),
      0,
      "globalExitRootMap"
    );
  }

  /// @dev Inserts the global exit root `deposit` was made under into X Layer's global exit root
  /// manager, then claims `deposit` on X Layer. Asserts the bridge mints the deposit's amount of
  /// `XLayer.RESOURCE` to its recipient. Runs on the selected fork, which must be the X Layer fork.
  function _claimUniOnXLayer(UniDeposit memory deposit) internal {
    IERC20 uni = IERC20(XLayer.RESOURCE);

    // Insert the global exit root on X Layer, as X Layer's updater does once it reads the root
    // from Ethereum.
    IGlobalExitRootManagerL2 manager = xLayerExitRootManager(XLayer.TOKEN_BRIDGE);
    vm.prank(manager.globalExitRootUpdater());
    manager.insertGlobalExitRoot(globalExitRoot(deposit.mainnetExitRoot, deposit.rollupExitRoot));

    // Claim the deposit. The searcher made it on Ethereum, so the claim proves the leaf against the
    // mainnet exit root alone and leaves the rollup exit root proof empty.
    uint256 balanceBefore = uni.balanceOf(deposit.recipient);
    uint256 supplyBefore = uni.totalSupply();
    UniClaim memory claim;
    claim.bridge = XLayer.TOKEN_BRIDGE;
    claim.globalIndex = GLOBAL_INDEX_MAINNET_FLAG | deposit.leaf.index;
    claim.localExitRootProof = deposit.leaf.proof;
    claim.mainnetExitRoot = deposit.mainnetExitRoot;
    claim.rollupExitRoot = deposit.rollupExitRoot;
    claim.destinationNetwork = XLAYER_NETWORK_ID;
    claim.destinationAddress = deposit.recipient;
    claim.amount = deposit.amount;
    _claimUni(claim);

    // Assert the bridge minted the deposit's amount to its recipient.
    assertEq(uni.balanceOf(deposit.recipient) - balanceBefore, deposit.amount, "uni.claimed");
    assertEq(uni.totalSupply() - supplyBefore, deposit.amount, "uni.totalSupply.claimed");
  }

  /// @dev Settles X Layer's local exit root, which holds `leaf`, on Ethereum, then claims the
  /// deposit of `amount` UNI to the burn address that appended `leaf`. Asserts the Ethereum bridge
  /// pays `amount` of its escrowed UNI to the burn address. Starts on the X Layer fork and leaves
  /// the Ethereum fork selected.
  function _claimBurnOnEthereum(ExitLeaf memory leaf, uint256 amount) internal {
    bytes32 localExitRoot =
      _assertUniExitLeaf(XLayer.TOKEN_BRIDGE, leaf, ETHEREUM_NETWORK_ID, BURN_ADDRESS, amount);

    vm.selectFork(mainnetFork);
    IERC20 uni = IERC20(uniswap.ethereum.uni);

    // Claim the deposit. The releaser made it on X Layer, so the claim proves the leaf against X
    // Layer's local exit root, and that root against the rollup exit root.
    UniClaim memory claim;
    claim.bridge = ETHEREUM_TOKEN_BRIDGE;
    claim.globalIndex = (uint256(XLAYER_ROLLUP_INDEX) << 32) | leaf.index;
    claim.localExitRootProof = leaf.proof;
    (claim.rollupExitRoot, claim.rollupExitRootProof) = _settleXLayerExitRoot(localExitRoot);
    claim.mainnetExitRoot = ethereumExitRootManager().lastMainnetExitRoot();
    claim.destinationNetwork = ETHEREUM_NETWORK_ID;
    claim.destinationAddress = BURN_ADDRESS;
    claim.amount = amount;
    uint256 escrowedBefore = uni.balanceOf(ETHEREUM_TOKEN_BRIDGE);
    uint256 burnedBefore = uni.balanceOf(BURN_ADDRESS);
    _claimUni(claim);

    // Assert the bridge paid `amount` of its escrowed UNI to the burn address.
    assertEq(escrowedBefore - uni.balanceOf(ETHEREUM_TOKEN_BRIDGE), amount, "uni.ethereumBridge");
    assertEq(uni.balanceOf(BURN_ADDRESS) - burnedBefore, amount, "uni.burnAddress");
  }

  /// @dev Submits `claim` of a deposit of Ethereum UNI to its bridge, and asserts the bridge emits
  /// the claim. Runs on the selected fork, which must be the fork `claim.bridge` is on.
  function _claimUni(UniClaim memory claim) internal {
    vm.expectEmit(claim.bridge);
    emit IXLayerBridgeFull.ClaimEvent(
      claim.globalIndex,
      ETHEREUM_NETWORK_ID,
      uniswap.ethereum.uni,
      claim.destinationAddress,
      claim.amount
    );
    IXLayerBridgeFull(claim.bridge)
      .claimAsset(
        claim.localExitRootProof,
        claim.rollupExitRootProof,
        claim.globalIndex,
        claim.mainnetExitRoot,
        claim.rollupExitRoot,
        ETHEREUM_NETWORK_ID,
        uniswap.ethereum.uni,
        claim.destinationNetwork,
        claim.destinationAddress,
        claim.amount,
        uniMetadata()
      );
  }

  /// @dev Pushes a rollup exit root holding `localExitRoot` as X Layer's local exit root to the
  /// global exit root manager on Ethereum, and returns that rollup exit root with the merkle proof
  /// of X Layer's leaf in it. Runs on the selected fork, which must be the Ethereum fork.
  function _settleXLayerExitRoot(bytes32 localExitRoot)
    internal
    returns (bytes32 rollupExitRoot, bytes32[32] memory rollupProof)
  {
    IGlobalExitRootManagerL1 manager = ethereumExitRootManager();
    IRollupManager rollupManager = IRollupManager(manager.rollupManager());

    // Read each rollup's last settled local exit root. Rollup ID `i + 1` is leaf `i` of the rollup
    // exit tree.
    bytes32[] memory localExitRoots = new bytes32[](rollupManager.rollupCount());
    for (uint32 i; i < localExitRoots.length; i++) {
      (,,,, localExitRoots[i],,,,,,,) = rollupManager.rollupIDToRollupData(i + 1);
    }

    // Assert the RollupManager keeps X Layer's local exit root at `XLAYER_ROLLUP_INDEX`, the index
    // the tree below and the claim's `globalIndex` use. Rollup ID `XLAYER_ROLLUP_INDEX + 1` is leaf
    // `XLAYER_ROLLUP_INDEX`.
    assertEq(
      rollupManager.chainIDToRollupID(uint64(ChainId.XLayer)),
      XLAYER_ROLLUP_INDEX + 1,
      "chainIDToRollupID"
    );

    // Assert we build the rollup exit tree as the RollupManager does.
    (rollupExitRoot,) = merkleRootAndProof(localExitRoots, XLAYER_ROLLUP_INDEX);
    assertEq(rollupExitRoot, rollupManager.getRollupExitRoot(), "getRollupExitRoot");

    // Replace X Layer's leaf with `localExitRoot`, and push the new rollup exit root to the global
    // exit root manager, as the RollupManager does once it settles X Layer's certificate.
    localExitRoots[XLAYER_ROLLUP_INDEX] = localExitRoot;
    (rollupExitRoot, rollupProof) = merkleRootAndProof(localExitRoots, XLAYER_ROLLUP_INDEX);
    vm.prank(address(rollupManager));
    manager.updateExitRoot(rollupExitRoot);
  }

  /// @dev Asserts `leaf`'s proof places a deposit of `amount` Ethereum UNI to `destinationAddress`
  /// on `destinationNetwork` under `bridge`'s local exit root, and returns that root. Fails if
  /// `BRANCH_SLOT` is wrong and `leaf.index` is non-zero; the proof of leaf 0 reads no stored
  /// subtree root. Reads `bridge` on the selected fork.
  function _assertUniExitLeaf(
    address bridge,
    ExitLeaf memory leaf,
    uint32 destinationNetwork,
    address destinationAddress,
    uint256 amount
  ) internal view returns (bytes32 localExitRoot) {
    bytes32 leafValue = IXLayerBridgeFull(bridge)
      .getLeafValue(
        0,
        ETHEREUM_NETWORK_ID,
        uniswap.ethereum.uni,
        destinationNetwork,
        destinationAddress,
        amount,
        keccak256(uniMetadata())
      );
    localExitRoot = IXLayerBridgeFull(bridge).getRoot();
    assertEq(
      IXLayerBridgeFull(bridge).calculateRoot(leafValue, leaf.proof, leaf.index),
      localExitRoot,
      "localExitRoot"
    );
  }
}
