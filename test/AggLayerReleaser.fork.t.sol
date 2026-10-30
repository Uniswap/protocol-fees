// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Currency} from "v4-core/types/Currency.sol";

import {AggLayerReleaser} from "../src/releasers/AggLayerReleaser.sol";
import {ITokenJar} from "../src/interfaces/ITokenJar.sol";
import {IOwned} from "../src/interfaces/base/IOwned.sol";
import {IAggLayerBridge} from "../src/interfaces/external/IAggLayerBridge.sol";

/// @dev Bridge-minted `TokenWrapped`; only the bridge can mint
interface ITokenWrapped {
  function mint(address to, uint256 value) external;
}

/// @dev `PolygonZkEVMBridgeV2` views not in `IAggLayerBridge`
interface IAggLayerBridgeViews {
  function depositCount() external view returns (uint256);
  function getRoot() external view returns (bytes32);
  function globalExitRootManager() external view returns (address);
}

/// @dev `PolygonZkEVMGlobalExitRootL2`, updated by the bridge when `forceUpdateGlobalExitRoot`
interface IGlobalExitRootL2 {
  function lastRollupExitRoot() external view returns (bytes32);
}

/// @notice Runs `AggLayerReleaser` against the real AggLayer unified bridge and TokenJar on X Layer
/// @dev Complements the mock bridge in AggLayerReleaser.t.sol. The X Layer bridge is the
/// pre-sovereign `PolygonZkEVMBridgeV2` lineage, so the remap and legacy-removal path of the
/// sovereign bridge cannot be exercised here; the unmapped-token test instead confirms the real
/// bridge escrows such a token rather than reverting, which is the behavior the mock models.
contract AggLayerReleaserForkTest is Test {
  uint256 internal constant FORK_BLOCK = 74_354_718;
  uint256 internal constant X_LAYER_CHAIN_ID = 196;

  uint32 internal constant ETHEREUM_NETWORK_ID = 0;
  uint32 internal constant X_LAYER_NETWORK_ID = 3;

  /// @dev AggLayer unified bridge on X Layer
  /// https://www.oklink.com/xlayer/address/0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe
  address internal constant BRIDGE = 0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe;

  /// @dev AggLayer-wrapped UNI on X Layer (`TokenWrapped`, origin network 0, origin L1 UNI)
  /// https://www.oklink.com/xlayer/address/0x2548C94A3092494dB3aF864cc2cF781a72f55678
  address internal constant RESOURCE = 0x2548C94A3092494dB3aF864cc2cF781a72f55678;

  /// @dev OP Stack `OptimismMintableERC20` UNI on X Layer, unknown to the unified bridge
  /// https://www.oklink.com/xlayer/address/0x57FB37d035e6Ad0E687E0a50dC3F515691deB815
  address internal constant OP_STACK_UNI = 0x57FB37d035e6Ad0E687E0a50dC3F515691deB815;

  /// @dev UNI on Ethereum mainnet
  address internal constant L1_RESOURCE = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

  /// @dev X Layer TokenJar, owned by the UNI Timelock's CrossChainAccount
  /// https://www.oklink.com/xlayer/address/0x8Dd8B6D56e4a4A158EDbBfE7f2f703B8FFC1a754
  address internal constant TOKEN_JAR = 0x8Dd8B6D56e4a4A158EDbBfE7f2f703B8FFC1a754;

  address internal constant BURN_ADDRESS = address(0xdead);
  uint256 internal constant THRESHOLD = 2000e18;
  uint256 internal constant FEE_AMOUNT = 10 ether;

  ITokenJar internal tokenJar = ITokenJar(TOKEN_JAR);
  AggLayerReleaser internal releaser;

  address internal alice = makeAddr("alice");

  function setUp() public {
    bool shouldRun = vm.envOr("SHOULD_FORK_TEST", false);
    vm.skip(!shouldRun);

    vm.createSelectFork("xlayer", FORK_BLOCK);
    assertEq(block.chainid, X_LAYER_CHAIN_ID, "Not on X Layer");

    releaser = new AggLayerReleaser(BRIDGE, RESOURCE, L1_RESOURCE, THRESHOLD, TOKEN_JAR);
    _setJarReleaser(address(releaser));

    vm.deal(TOKEN_JAR, FEE_AMOUNT);
  }

  function test_fork_bridgeMapsResourceToL1Uni() public view {
    IAggLayerBridge bridge = IAggLayerBridge(BRIDGE);
    assertEq(bridge.networkID(), X_LAYER_NETWORK_ID);

    (uint32 originNetwork, address originTokenAddress) = bridge.wrappedTokenToTokenInfo(RESOURCE);
    assertEq(originNetwork, ETHEREUM_NETWORK_ID);
    assertEq(originTokenAddress, L1_RESOURCE);
    assertEq(bridge.getTokenWrappedAddress(ETHEREUM_NETWORK_ID, L1_RESOURCE), RESOURCE);
  }

  function test_fork_release_burnsWrappedUniAndBridgesToEthereumBurnAddress() public {
    _mintWrappedUni(alice, THRESHOLD);

    Currency[] memory assets = new Currency[](1);
    assets[0] = Currency.wrap(address(0));

    uint256 supplyBefore = IERC20(RESOURCE).totalSupply();
    uint256 depositCountBefore = IAggLayerBridgeViews(BRIDGE).depositCount();
    bytes32 rootBefore = IAggLayerBridgeViews(BRIDGE).getRoot();

    vm.startPrank(alice);
    IERC20(RESOURCE).approve(address(releaser), THRESHOLD);

    // The V2 bridge encodes the wrapped token's metadata into the leaf
    vm.expectEmit(BRIDGE);
    emit IAggLayerBridge.BridgeEvent(
      0,
      ETHEREUM_NETWORK_ID,
      L1_RESOURCE,
      ETHEREUM_NETWORK_ID,
      BURN_ADDRESS,
      THRESHOLD,
      abi.encode("Uniswap", "UNI", uint8(18)),
      uint32(depositCountBefore)
    );
    releaser.release(releaser.nonce(), assets, alice);
    vm.stopPrank();

    // Stage 1: fee assets released to the recipient
    assertEq(alice.balance, FEE_AMOUNT);
    assertEq(TOKEN_JAR.balance, 0);

    // Stage 2: the bridge burned the wrapped UNI directly, without spending the allowance
    assertEq(IERC20(RESOURCE).balanceOf(alice), 0);
    assertEq(IERC20(RESOURCE).balanceOf(address(releaser)), 0);
    assertEq(IERC20(RESOURCE).balanceOf(BRIDGE), 0);
    assertEq(IERC20(RESOURCE).totalSupply(), supplyBefore - THRESHOLD);
    assertEq(IERC20(RESOURCE).allowance(address(releaser), BRIDGE), THRESHOLD);

    // A new leaf was appended and, with `forceUpdateGlobalExitRoot`, pushed to the GER manager
    bytes32 rootAfter = IAggLayerBridgeViews(BRIDGE).getRoot();
    assertEq(IAggLayerBridgeViews(BRIDGE).depositCount(), depositCountBefore + 1);
    assertNotEq(rootAfter, rootBefore);
    address gerManager = IAggLayerBridgeViews(BRIDGE).globalExitRootManager();
    assertEq(IGlobalExitRootL2(gerManager).lastRollupExitRoot(), rootAfter);
  }

  /// @dev The OP Stack UNI is a different asset the unified bridge does not recognize
  function test_fork_revert_release_opStackUni() public {
    AggLayerReleaser misconfigured =
      new AggLayerReleaser(BRIDGE, OP_STACK_UNI, L1_RESOURCE, THRESHOLD, TOKEN_JAR);
    _setJarReleaser(address(misconfigured));
    deal(OP_STACK_UNI, alice, THRESHOLD);

    Currency[] memory assets = new Currency[](1);
    assets[0] = Currency.wrap(address(0));

    vm.startPrank(alice);
    IERC20(OP_STACK_UNI).approve(address(misconfigured), THRESHOLD);
    uint256 currentNonce = misconfigured.nonce();
    vm.expectRevert(AggLayerReleaser.ResourceNotWrappedL1Resource.selector);
    misconfigured.release(currentNonce, assets, alice);
    vm.stopPrank();

    assertEq(TOKEN_JAR.balance, FEE_AMOUNT);
    assertEq(IERC20(OP_STACK_UNI).balanceOf(alice), THRESHOLD);
  }

  /// @dev The real bridge escrows a token it has no mapping for as a token native to X Layer,
  /// pulling it through the caller's allowance. This is what `_afterRelease` guards against, and
  /// what the mock bridge models for a deleted legacy mapping.
  function test_fork_bridge_escrowsUnmappedTokenAsNative() public {
    MockERC20 unmapped = new MockERC20("Unmapped", "UNM", 18);
    unmapped.mint(alice, THRESHOLD);

    uint256 depositCountBefore = IAggLayerBridgeViews(BRIDGE).depositCount();

    vm.startPrank(alice);
    unmapped.approve(BRIDGE, THRESHOLD);
    vm.expectEmit(BRIDGE);
    emit IAggLayerBridge.BridgeEvent(
      0,
      X_LAYER_NETWORK_ID,
      address(unmapped),
      ETHEREUM_NETWORK_ID,
      BURN_ADDRESS,
      THRESHOLD,
      abi.encode("Unmapped", "UNM", uint8(18)),
      uint32(depositCountBefore)
    );
    IAggLayerBridge(BRIDGE)
      .bridgeAsset(ETHEREUM_NETWORK_ID, BURN_ADDRESS, THRESHOLD, address(unmapped), true, "");
    vm.stopPrank();

    assertEq(unmapped.balanceOf(BRIDGE), THRESHOLD);
    assertEq(unmapped.balanceOf(alice), 0);
  }

  function _setJarReleaser(address newReleaser) internal {
    vm.prank(IOwned(TOKEN_JAR).owner());
    tokenJar.setReleaser(newReleaser);
  }

  function _mintWrappedUni(address to, uint256 amount) internal {
    vm.prank(BRIDGE);
    ITokenWrapped(RESOURCE).mint(to, amount);
  }
}
