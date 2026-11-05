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
  readNewReleaser
} from "../../../../script/proposal-103/x-layer/ReplaceXLayerReleaser.s.sol";
import {
  DeployAggLayerReleaser
} from "../../../../script/proposal-103/x-layer/prereq/DeployAggLayerReleaser.s.sol";
import {RECORD_NAME, Records, XLayer} from "../../../../script/proposal-103/x-layer/Constants.sol";
import {IAggLayerBridge} from "../../../../src/interfaces/external/IAggLayerBridge.sol";
import {executeAsTimelock} from "../../../utils/TimelockExecution.sol";

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

/// @dev Ethereum's network ID in the AggLayer unified bridge.
uint32 constant ETHEREUM_NETWORK_ID = 0;

/// @dev The unified bridge's count of deposits, which `IAggLayerBridge` does not expose.
interface IAggLayerBridgeDepositCount {
  function depositCount() external view returns (uint256);
}

/// @dev The prerequisite script, pointed at the specified record.
contract DeployAggLayerReleaserHarness is DeployAggLayerReleaser {
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

  /// @dev Executes the proposal on Ethereum, then on X Layer executes the deposit transaction the
  /// proposal created through X Layer's OptimismPortal, and asserts the TokenJar accepts releases
  /// from the new releaser and refuses them from the old one.
  function test_relayMessage() public {
    string memory recordName = _loadNewReleaser("XLayerForkRelayTest");
    address newReleaser = readNewReleaser(recorder);
    ITokenJar tokenJar = ITokenJar(uniswap.xLayer.tokenJar);
    address oldReleaser = uniswap.xLayer.releaser;

    // Assert the TokenJar authorizes the old releaser's address before the message lands, to
    // isolate the below revert.
    vm.prank(oldReleaser);
    tokenJar.release(new address[](0), address(this));

    // Execute the proposal on Ethereum and its deposit transaction on X Layer. The helper also
    // asserts the proposal created exactly one deposit to the L2CrossDomainMessenger, and that the
    // deposit transaction does not revert.
    _executeProposalAndDeposit();

    // Assert the new releaser has been set on the TokenJar
    new ReplaceXLayerReleaserHarness(recordName).postflightXLayer();

    // Assert the TokenJar refuses the old releaser's address and accepts the new releaser's.
    // `test_release` covers a full release through the new releaser.
    vm.expectRevert(ITokenJar.Unauthorized.selector);
    vm.prank(oldReleaser);
    tokenJar.release(new address[](0), address(this));

    vm.prank(newReleaser);
    tokenJar.release(new address[](0), address(this));
  }

  /// @dev Executes the proposal, then has a searcher release one of the TokenJar's fee assets to
  /// itself through the new releaser, paying the threshold in UNI. Asserts the asset reaches the
  /// searcher, the bridge records a deposit of the threshold to the Ethereum burn address, and the
  /// UNI's supply on X Layer falls by the threshold.
  function test_release() public {
    // Assert X Layer is in the state the proposal assumes, including a deployed and handed-over
    // new releaser.
    string memory recordName = _loadNewReleaser("XLayerForkReleaseTest");
    new ReplaceXLayerReleaserHarness(recordName).preflightXLayer(XLAYER_BLOCK);

    _executeProposalAndDeposit();

    IReleaser releaser = IReleaser(readNewReleaser(recorder));
    IERC20 uni = IERC20(XLayer.RESOURCE);
    IERC20 feeAsset = IERC20(USDT_WOKB_V2_PAIR);
    address tokenJar = uniswap.xLayer.tokenJar;
    address searcher = makeAddr("searcher");

    // Give the searcher the threshold in UNI and have it approve the releaser to take it.
    // TODO: pay the amount the deployed releaser requires, if it is not `threshold()`.
    uint256 threshold = releaser.threshold();
    deal(address(uni), searcher, threshold, true);
    vm.prank(searcher);
    uni.approve(address(releaser), threshold);

    // Assert the TokenJar holds the fee asset, so the payout assertions below witness a transfer.
    uint256 feeAssetInJar = feeAsset.balanceOf(tokenJar);
    assertGt(feeAssetInJar, 0, "feeAsset.tokenJar.before");
    uint256 uniSupplyBefore = uni.totalSupply();

    address[] memory assets = new address[](1);
    assets[0] = address(feeAsset);
    uint256 nonce = releaser.nonce();

    // Assert the release deposits the threshold in the bridge, to reach the Ethereum burn address
    // as Ethereum UNI. The bridge encodes the wrapped token's metadata into the deposit.
    vm.expectEmit(XLayer.TOKEN_BRIDGE);
    emit IAggLayerBridge.BridgeEvent(
      0,
      ETHEREUM_NETWORK_ID,
      uniswap.ethereum.uni,
      ETHEREUM_NETWORK_ID,
      BURN_ADDRESS,
      threshold,
      abi.encode("Uniswap", "UNI", uint8(18)),
      uint32(IAggLayerBridgeDepositCount(XLayer.TOKEN_BRIDGE).depositCount())
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
    new DeployAggLayerReleaserHarness(testRecordName).run();

    // `run()` initialized the harness's own recorder. This one is the test's handle on the same
    // file, which `readNewReleaser` and `buildReplaceReleaserCall` require initialized.
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

  /// @dev Executes the proposal on Ethereum, then on X Layer executes the deposit transaction the
  /// proposal created through X Layer's OptimismPortal, as X Layer does once it reads the deposit
  /// from Ethereum. Asserts the proposal created exactly one deposit to the L2CrossDomainMessenger
  /// and that the deposit transaction does not revert. Builds the proposal from `recorder`, which
  /// must be initialized. Leaves the X Layer fork selected.
  function _executeProposalAndDeposit() internal {
    vm.selectFork(mainnetFork);
    Call[] memory calls = LibCall.newCalls([buildReplaceReleaserCall(uniswap, recorder)]);
    address portal = IL1CrossDomainMessenger(uniswap.ethereum.bridge.xLayer).PORTAL();

    vm.recordLogs();
    executeAsTimelock(vm, uniswap.ethereum.timelock, calls);
    (address from, address to, uint256 value, uint64 gasLimit, bytes memory data) =
      _depositFromLogs(vm.getRecordedLogs(), portal);

    vm.selectFork(xLayerFork);

    // Send the deposit's calldata from its sender to its recipient with the gas its execution gets
    // on X Layer: the deposit's gas limit less the transaction's intrinsic gas. The calldata is
    // the L2CrossDomainMessenger's `relayMessage`, which forwards the proposal's message to the
    // CrossChainAccount. If the message's gas limit is too low, the messenger records the message
    // as failed instead of reverting, and the postflight check catches it.
    vm.prank(from);
    (bool success,) = to.call{value: value, gas: gasLimit - _intrinsicGas(data)}(data);
    require(success, "deposit reverted");
  }

  /// @dev Returns the fields of the one `TransactionDeposited` in `logs` that X Layer's
  /// OptimismPortal at `portal` emitted for a deposit from X Layer's L1CrossDomainMessenger to the
  /// L2CrossDomainMessenger.
  function _depositFromLogs(Vm.Log[] memory logs, address portal)
    internal
    view
    returns (address from, address to, uint256 value, uint64 gasLimit, bytes memory data)
  {
    // event TransactionDeposited(
    //    address indexed from,
    //    address indexed to,
    //    uint256 indexed version,
    //    bytes opaqueData
    // );
    //
    // The portal names the L1 messenger by its aliased address, which is the deposit's sender on
    // X Layer.
    from = AddressAliasHelper.applyL1ToL2Alias(uniswap.ethereum.bridge.xLayer);
    to = Predeploys.L2_CROSS_DOMAIN_MESSENGER;

    uint256 found;
    for (uint256 i; i < logs.length; i++) {
      if (logs[i].emitter != portal) continue;
      if (logs[i].topics[0] != IOptimismPortal2.TransactionDeposited.selector) continue;
      // An indexed address is left-padded to the 32-byte topic.
      if (logs[i].topics[1] != bytes32(uint256(uint160(from)))) continue;
      if (logs[i].topics[2] != bytes32(uint256(uint160(to)))) continue;
      // Assert the deposit is version 0, the `opaqueData` layout `decodeOpaqueData` reads.
      assertEq(uint256(logs[i].topics[3]), 0, "TransactionDeposited.version");
      (value, gasLimit, data) = this.decodeOpaqueData(abi.decode(logs[i].data, (bytes)));
      found++;
    }
    // There should be exactly one such event.
    assertEq(found, 1, "TransactionDeposited.count");
  }

  /// @dev Decodes a version 0 deposit's `opaqueData` into the fields the deposit transaction uses.
  /// External so it can slice calldata.
  ///
  /// The Optimism contracts have no Solidity decoder for `opaqueData`, so we write one here. The
  /// layout is `mint` (32 bytes), `value` (32 bytes), `gasLimit` (8 bytes), `isCreation` (1 byte),
  /// then `data`. Two sources, both in `lib/optimism`, confirm it:
  ///
  /// - The encoder: `OptimismPortal2.depositTransaction` packs it as
  ///   `abi.encodePacked(msg.value, _value, _gasLimit, _isCreation, _data)`, in
  ///   `packages/contracts-bedrock/src/L1/OptimismPortal2.sol`.
  /// - The decoder: the OP Stack node builds the deposit transaction from the same layout in
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
  /// We subtract it on the assumption that X Layer charges deposit transactions intrinsic gas like
  /// any other transaction. If it does not, execution gets more gas than we give it, so the test
  /// errs strict.
  function _intrinsicGas(bytes memory data) internal pure returns (uint256 gas) {
    gas = 21_000;
    for (uint256 i; i < data.length; i++) {
      gas += data[i] == 0 ? 4 : 16;
    }
  }
}
