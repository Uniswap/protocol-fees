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
  DeployXLayerReleaser
} from "../../../../script/proposal-103/x-layer/prereq/DeployXLayerReleaser.s.sol";
import {RECORD_NAME, Records, XLayer} from "../../../../script/proposal-103/x-layer/Constants.sol";
import {IXLayerBridge} from "../../../../src/interfaces/external/IXLayerBridge.sol";
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

/// @dev Ethereum's network ID in the unified bridge.
uint32 constant ETHEREUM_NETWORK_ID = 0;

/// @dev X Layer's network ID in the unified bridge.
uint32 constant XLAYER_NETWORK_ID = 3;

/// @dev The unified bridge on Ethereum, which escrows UNI bridged to X Layer. It has the
/// same address as `XLayer.TOKEN_BRIDGE`.
/// https://etherscan.io/address/0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe
address constant ETHEREUM_TOKEN_BRIDGE = 0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe;

/// @dev The storage slot of `_branch[0]` in the unified bridge, on Ethereum and on X Layer.
/// `DepositContractBase` declares `bytes32[32] _branch` and then `depositCount` after
/// OpenZeppelin's `Initializable` and `ReentrancyGuardUpgradeable`, which take slots 0 to 50, so
/// `_branch` takes slots 51 to 82 and `depositCount` slot 83.
uint256 constant BRANCH_SLOT = 51;

/// @dev The height of the unified bridge's exit trees and of the RollupManager's rollup exit tree.
uint256 constant EXIT_TREE_HEIGHT = 32;

/// @dev The bit a claim's `globalIndex` sets when the deposit it claims was made on Ethereum. The
/// low 32 bits then hold the deposit's index in Ethereum's exit tree.
uint256 constant GLOBAL_INDEX_MAINNET_FLAG = 1 << 64;

/// @dev X Layer's index in the RollupManager's rollup exit tree: its rollup ID, which equals its
/// network ID, less one. A claim of a deposit made on X Layer puts it in bits 32 to 63 of
/// `globalIndex`.
uint32 constant XLAYER_ROLLUP_INDEX = XLAYER_NETWORK_ID - 1;

/// @dev Functions of the unified bridge that `IXLayerBridge` does not expose.
interface IXLayerBridgeFull {
  /// @dev Emitted when the bridge pays out a claimed deposit.
  event ClaimEvent(
    uint256 globalIndex,
    uint32 originNetwork,
    address originAddress,
    address destinationAddress,
    uint256 amount
  );

  function depositCount() external view returns (uint256);
  function getRoot() external view returns (bytes32);
  function globalExitRootManager() external view returns (address);

  function getLeafValue(
    uint8 leafType,
    uint32 originNetwork,
    address originAddress,
    uint32 destinationNetwork,
    address destinationAddress,
    uint256 amount,
    bytes32 metadataHash
  ) external pure returns (bytes32);

  function calculateRoot(bytes32 leafHash, bytes32[32] calldata smtProof, uint32 index)
    external
    pure
    returns (bytes32);

  function claimAsset(
    bytes32[32] calldata smtProofLocalExitRoot,
    bytes32[32] calldata smtProofRollupExitRoot,
    uint256 globalIndex,
    bytes32 mainnetExitRoot,
    bytes32 rollupExitRoot,
    uint32 originNetwork,
    address originTokenAddress,
    uint32 destinationNetwork,
    address destinationAddress,
    uint256 amount,
    bytes calldata metadata
  ) external;
}

/// @dev The global exit root manager on Ethereum. The unified bridge updates its mainnet exit root
/// on a deposit, and the RollupManager updates its rollup exit root when a rollup settles.
interface IGlobalExitRootManagerL1 {
  function rollupManager() external view returns (address);
  function lastMainnetExitRoot() external view returns (bytes32);
  function lastRollupExitRoot() external view returns (bytes32);
  function getLastGlobalExitRoot() external view returns (bytes32);
  function updateExitRoot(bytes32 newRoot) external;
}

/// @dev The RollupManager on Ethereum, which keeps each rollup's last settled local exit
/// root.
interface IRollupManager {
  function rollupCount() external view returns (uint32);
  function getRollupExitRoot() external view returns (bytes32);
  function rollupIDToRollupData(uint32 rollupID)
    external
    view
    returns (
      address rollupContract,
      uint64 chainID,
      address verifier,
      uint64 forkID,
      bytes32 lastLocalExitRoot,
      uint64 lastBatchSequenced,
      uint64 lastVerifiedBatch,
      uint64 legacyLastPendingState,
      uint64 legacyLastPendingStateConsolidated,
      uint64 lastVerifiedBatchBeforeUpgrade,
      uint64 rollupTypeID,
      uint8 rollupVerifierType
    );
}

/// @dev A leaf a deposit appends to a unified bridge's local exit tree, with its merkle proof.
struct ExitLeaf {
  uint32 index;
  bytes32[32] proof;
}

/// @dev The arguments of a claim of a deposit of Ethereum UNI that vary between claims, and the
/// bridge the claim is submitted to.
struct UniClaim {
  address bridge;
  uint256 globalIndex;
  bytes32[32] localExitRootProof;
  bytes32[32] rollupExitRootProof;
  bytes32 mainnetExitRoot;
  bytes32 rollupExitRoot;
  uint32 destinationNetwork;
  address destinationAddress;
  uint256 amount;
}

/// @dev A deposit of UNI in the Ethereum unified bridge, with what a claim of it on X Layer needs.
struct UniDeposit {
  address recipient;
  uint256 amount;
  ExitLeaf leaf;
  bytes32 mainnetExitRoot;
  bytes32 rollupExitRoot;
}

/// @dev The global exit root manager on X Layer, into which X Layer's updater inserts Ethereum's
/// global exit roots.
interface IGlobalExitRootManagerL2 {
  function globalExitRootUpdater() external view returns (address);
  function insertGlobalExitRoot(bytes32 newRoot) external;
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

  /// @dev Executes the proposal, has a searcher bridge the threshold in UNI from Ethereum to X
  /// Layer, then has the searcher release one of the TokenJar's fee assets to itself through the
  /// new releaser, paying the threshold in the bridged UNI. Asserts the asset reaches the searcher,
  /// the bridge records a deposit of the threshold to the Ethereum burn address, and the UNI's
  /// supply on X Layer falls by the threshold. Then settles X Layer's exit root on Ethereum, claims
  /// the deposit there, and asserts the Ethereum bridge pays the threshold to the burn address.
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

    // Have the searcher bridge the threshold in UNI from Ethereum to X Layer, and approve the
    // releaser to take it.
    // TODO: pay the amount the deployed releaser requires, if it is not `threshold()`.
    uint256 threshold = releaser.threshold();
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
    ExitLeaf memory burnLeaf = _nextExitLeaf(XLayer.TOKEN_BRIDGE);

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
      _uniMetadata(),
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
    deposit.leaf = _nextExitLeaf(ETHEREUM_TOKEN_BRIDGE);

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
      _uniMetadata(),
      deposit.leaf.index
    );
    IXLayerBridge(ETHEREUM_TOKEN_BRIDGE)
      .bridgeAsset(XLAYER_NETWORK_ID, to, amount, address(uni), true, "");
    vm.stopPrank();

    // Assert the bridge escrowed the UNI.
    assertEq(uni.balanceOf(ETHEREUM_TOKEN_BRIDGE) - escrowedBefore, amount, "uni.ethereumBridge");

    deposit.mainnetExitRoot =
      _assertUniExitLeaf(ETHEREUM_TOKEN_BRIDGE, deposit.leaf, XLAYER_NETWORK_ID, to, amount);

    // Assert the deposit pushed the bridge's new exit root to the global exit root manager.
    IGlobalExitRootManagerL1 manager = IGlobalExitRootManagerL1(bridge.globalExitRootManager());
    assertEq(manager.lastMainnetExitRoot(), deposit.mainnetExitRoot, "lastMainnetExitRoot");
    deposit.rollupExitRoot = manager.lastRollupExitRoot();
    assertEq(
      manager.getLastGlobalExitRoot(),
      _globalExitRoot(deposit.mainnetExitRoot, deposit.rollupExitRoot),
      "getLastGlobalExitRoot"
    );
  }

  /// @dev Inserts the global exit root `deposit` was made under into X Layer's global exit root
  /// manager, then claims `deposit` on X Layer. Asserts the bridge mints the deposit's amount of
  /// `XLayer.RESOURCE` to its recipient. Runs on the selected fork, which must be the X Layer fork.
  function _claimUniOnXLayer(UniDeposit memory deposit) internal {
    IERC20 uni = IERC20(XLayer.RESOURCE);

    // Insert the global exit root on X Layer, as X Layer's updater does once it reads the root
    // from Ethereum.
    IGlobalExitRootManagerL2 manager =
      IGlobalExitRootManagerL2(IXLayerBridgeFull(XLayer.TOKEN_BRIDGE).globalExitRootManager());
    vm.prank(manager.globalExitRootUpdater());
    manager.insertGlobalExitRoot(_globalExitRoot(deposit.mainnetExitRoot, deposit.rollupExitRoot));

    // Claim the deposit. It was made on Ethereum, so the claim proves the leaf against the mainnet
    // exit root alone and leaves the rollup exit root proof empty.
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

    // Claim the deposit. It was made on X Layer, so the claim proves the leaf against X Layer's
    // local exit root, and that root against the rollup exit root.
    UniClaim memory claim;
    claim.bridge = ETHEREUM_TOKEN_BRIDGE;
    claim.globalIndex = (uint256(XLAYER_ROLLUP_INDEX) << 32) | leaf.index;
    claim.localExitRootProof = leaf.proof;
    (claim.rollupExitRoot, claim.rollupExitRootProof) = _settleXLayerExitRoot(localExitRoot);
    claim.mainnetExitRoot = _ethereumExitRootManager().lastMainnetExitRoot();
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
        _uniMetadata()
      );
  }

  /// @dev Pushes a rollup exit root holding `localExitRoot` as X Layer's local exit root to the
  /// global exit root manager on Ethereum, and returns that rollup exit root with the merkle proof
  /// of X Layer's leaf in it. Runs on the selected fork, which must be the Ethereum fork.
  function _settleXLayerExitRoot(bytes32 localExitRoot)
    internal
    returns (bytes32 rollupExitRoot, bytes32[32] memory rollupProof)
  {
    IGlobalExitRootManagerL1 manager = _ethereumExitRootManager();
    IRollupManager rollupManager = IRollupManager(manager.rollupManager());

    // Read each rollup's last settled local exit root. Rollup ID `i + 1` is leaf `i` of the rollup
    // exit tree.
    bytes32[] memory localExitRoots = new bytes32[](rollupManager.rollupCount());
    for (uint32 i; i < localExitRoots.length; i++) {
      (,,,, localExitRoots[i],,,,,,,) = rollupManager.rollupIDToRollupData(i + 1);
    }

    // Assert we build the rollup exit tree as the RollupManager does.
    (rollupExitRoot,) = _merkleRootAndProof(localExitRoots, XLAYER_ROLLUP_INDEX);
    assertEq(rollupExitRoot, rollupManager.getRollupExitRoot(), "getRollupExitRoot");

    // Replace X Layer's leaf with `localExitRoot`, and push the new rollup exit root to the global
    // exit root manager, as the RollupManager does once it settles X Layer's certificate.
    localExitRoots[XLAYER_ROLLUP_INDEX] = localExitRoot;
    (rollupExitRoot, rollupProof) = _merkleRootAndProof(localExitRoots, XLAYER_ROLLUP_INDEX);
    vm.prank(address(rollupManager));
    manager.updateExitRoot(rollupExitRoot);
  }

  /// @dev Returns the global exit root manager of the unified bridge on Ethereum. Reads the bridge
  /// on the selected fork, which must be the Ethereum fork.
  function _ethereumExitRootManager() internal view returns (IGlobalExitRootManagerL1) {
    return
      IGlobalExitRootManagerL1(IXLayerBridgeFull(ETHEREUM_TOKEN_BRIDGE).globalExitRootManager());
  }

  /// @dev Returns the leaf the next deposit in `bridge` will append to its local exit tree, with
  /// the leaf's merkle proof. Reads `bridge` on the selected fork.
  function _nextExitLeaf(address bridge) internal view returns (ExitLeaf memory leaf) {
    // The next deposit appends its leaf at index `depositCount`, so every subtree to the leaf's
    // right is empty. At each height where the index has a 1 bit, the leaf's sibling is the full
    // subtree to its left, whose root the bridge keeps in `_branch`. At every other height, the
    // sibling is the root of an empty subtree of that height.
    leaf.index = uint32(IXLayerBridgeFull(bridge).depositCount());
    bytes32 emptySubtreeRoot;
    for (uint256 height; height < EXIT_TREE_HEIGHT; height++) {
      leaf.proof[height] = (leaf.index >> height) & 1 == 1
        ? vm.load(bridge, bytes32(BRANCH_SLOT + height))
        : emptySubtreeRoot;
      emptySubtreeRoot = keccak256(abi.encodePacked(emptySubtreeRoot, emptySubtreeRoot));
    }
  }

  /// @dev Asserts `leaf`'s proof places a deposit of `amount` Ethereum UNI to `destinationAddress`
  /// on `destinationNetwork` under `bridge`'s local exit root, and returns that root. Fails if
  /// `BRANCH_SLOT` is wrong. Reads `bridge` on the selected fork.
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
        keccak256(_uniMetadata())
      );
    localExitRoot = IXLayerBridgeFull(bridge).getRoot();
    assertEq(
      IXLayerBridgeFull(bridge).calculateRoot(leafValue, leaf.proof, leaf.index),
      localExitRoot,
      "localExitRoot"
    );
  }

  /// @dev Returns the root of the exit tree whose first leaves are `leaves` and whose other leaves
  /// are empty, with the merkle proof of leaf `index`.
  function _merkleRootAndProof(bytes32[] memory leaves, uint256 index)
    internal
    pure
    returns (bytes32 root, bytes32[32] memory proof)
  {
    bytes32[] memory nodes = leaves;
    bytes32 emptySubtreeRoot;
    for (uint256 height; height < EXIT_TREE_HEIGHT; height++) {
      // Take the sibling of the node on the proof's path, which is empty past the last node.
      uint256 sibling = index ^ 1;
      proof[height] = sibling < nodes.length ? nodes[sibling] : emptySubtreeRoot;

      // Hash each pair of nodes into the level above, pairing an odd last node with an empty
      // subtree.
      bytes32[] memory parents = new bytes32[]((nodes.length + 1) / 2);
      for (uint256 i; i < parents.length; i++) {
        bytes32 right = 2 * i + 1 < nodes.length ? nodes[2 * i + 1] : emptySubtreeRoot;
        parents[i] = keccak256(abi.encodePacked(nodes[2 * i], right));
      }
      nodes = parents;
      index >>= 1;
      emptySubtreeRoot = keccak256(abi.encodePacked(emptySubtreeRoot, emptySubtreeRoot));
    }
    root = nodes[0];
  }

  /// @dev Returns the global exit root of `mainnetExitRoot` and `rollupExitRoot`, computed as the
  /// unified bridge computes it.
  function _globalExitRoot(bytes32 mainnetExitRoot, bytes32 rollupExitRoot)
    internal
    pure
    returns (bytes32)
  {
    return keccak256(abi.encodePacked(mainnetExitRoot, rollupExitRoot));
  }

  /// @dev Returns the metadata the unified bridge encodes into a deposit of Ethereum UNI or of its
  /// wrapped UNI: the name, symbol and decimals.
  function _uniMetadata() internal pure returns (bytes memory) {
    return abi.encode("Uniswap", "UNI", uint8(18));
  }
}
