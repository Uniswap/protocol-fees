// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Currency} from "v4-core/types/Currency.sol";

import {AggLayerReleaser} from "../src/releasers/AggLayerReleaser.sol";
import {TokenJar} from "../src/TokenJar.sol";
import {IReleaser} from "../src/interfaces/IReleaser.sol";
import {INonce} from "../src/interfaces/base/INonce.sol";
import {IAggLayerBridge} from "../src/interfaces/external/IAggLayerBridge.sol";

/// @dev Mock of the AggLayer unified bridge as deployed on an L2. Mirrors the two `bridgeAsset`
/// paths for a wrapped token: a bridge-minted token is burned from the caller directly, a
/// "not mintable" sovereign token is pulled through the caller's allowance and escrowed.
contract MockAggLayerBridge is IAggLayerBridge {
  error DestinationNetworkInvalid();
  error MsgValueNotZero();
  error OnlyNotEmergencyState();

  struct TokenInformation {
    uint32 originNetwork;
    address originTokenAddress;
  }

  uint32 public immutable override networkID;
  uint32 public depositCount;
  bool public emergencyState;

  mapping(address => TokenInformation) internal tokenInfo;
  mapping(address => bool) public wrappedAddressIsNotMintable;
  mapping(uint32 => mapping(address => address)) internal wrapped;

  constructor(uint32 _networkID) {
    networkID = _networkID;
  }

  function setWrappedToken(address token, uint32 originNetwork, address originTokenAddress)
    external
  {
    tokenInfo[token] = TokenInformation(originNetwork, originTokenAddress);
    wrapped[originNetwork][originTokenAddress] = token;
  }

  function setNotMintable(address token, bool notMintable) external {
    wrappedAddressIsNotMintable[token] = notMintable;
  }

  function setEmergencyState(bool active) external {
    emergencyState = active;
  }

  function bridgeAsset(
    uint32 destinationNetwork,
    address destinationAddress,
    uint256 amount,
    address token,
    bool,
    bytes calldata
  ) external payable override {
    require(!emergencyState, OnlyNotEmergencyState());
    require(destinationNetwork != networkID, DestinationNetworkInvalid());
    require(msg.value == 0, MsgValueNotZero());

    TokenInformation memory info = tokenInfo[token];
    require(info.originTokenAddress != address(0), "mock: only wrapped tokens supported");

    if (wrappedAddressIsNotMintable[token]) {
      MockERC20(token).transferFrom(msg.sender, address(this), amount);
    } else {
      MockERC20(token).burn(msg.sender, amount);
    }

    emit BridgeEvent(
      0,
      info.originNetwork,
      info.originTokenAddress,
      destinationNetwork,
      destinationAddress,
      amount,
      "",
      depositCount++
    );
  }

  function wrappedTokenToTokenInfo(address wrappedToken)
    external
    view
    override
    returns (uint32, address)
  {
    TokenInformation memory info = tokenInfo[wrappedToken];
    return (info.originNetwork, info.originTokenAddress);
  }

  function getTokenWrappedAddress(uint32 originNetwork, address originTokenAddress)
    external
    view
    override
    returns (address)
  {
    return wrapped[originNetwork][originTokenAddress];
  }
}

contract AggLayerReleaserTest is Test {
  AggLayerReleaser internal releaser;
  TokenJar internal tokenJar;
  MockERC20 internal resource;
  MockERC20 internal mockToken;
  MockAggLayerBridge internal bridge;

  address internal alice = makeAddr("alice");
  address internal bob = makeAddr("bob");
  address internal thresholdSetter = makeAddr("thresholdSetter");

  address internal constant L1_UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
  address internal constant BURN_ADDRESS = address(0xdead);
  uint32 internal constant ETHEREUM_NETWORK_ID = 0;
  uint32 internal constant X_LAYER_NETWORK_ID = 3;
  uint256 internal constant INITIAL_THRESHOLD = 2000e18;
  uint256 internal constant INITIAL_TOKEN_AMOUNT = 10_000e18;
  uint256 internal constant INITIAL_NATIVE_AMOUNT = 10 ether;

  function setUp() public {
    bridge = new MockAggLayerBridge(X_LAYER_NETWORK_ID);

    // Wrapped UNI minted by the bridge for Ethereum UNI
    resource = new MockERC20("Uniswap", "UNI", 18);
    bridge.setWrappedToken(address(resource), ETHEREUM_NETWORK_ID, L1_UNI);

    mockToken = new MockERC20("MockToken", "MTK", 18);
    tokenJar = new TokenJar();

    releaser = new AggLayerReleaser(
      address(bridge), address(resource), L1_UNI, INITIAL_THRESHOLD, address(tokenJar)
    );

    releaser.setThresholdSetter(thresholdSetter);
    tokenJar.setReleaser(address(releaser));

    resource.mint(alice, INITIAL_TOKEN_AMOUNT);
    resource.mint(bob, INITIAL_TOKEN_AMOUNT);
    mockToken.mint(address(tokenJar), INITIAL_TOKEN_AMOUNT);

    vm.deal(address(tokenJar), INITIAL_NATIVE_AMOUNT);
  }

  // ─── constructor ───

  function test_constructor() public view {
    assertEq(address(releaser.BRIDGE()), address(bridge));
    assertEq(releaser.L1_RESOURCE(), L1_UNI);
    assertEq(address(releaser.RESOURCE()), address(resource));
    assertEq(releaser.RESOURCE_RECIPIENT(), address(releaser));
    assertEq(releaser.threshold(), INITIAL_THRESHOLD);
    assertEq(address(releaser.TOKEN_JAR()), address(tokenJar));
    assertEq(releaser.owner(), address(this));
    assertEq(releaser.thresholdSetter(), thresholdSetter);
    assertEq(releaser.AGGLAYER_ETHEREUM_NETWORK_ID(), ETHEREUM_NETWORK_ID);
  }

  function test_revert_constructor_zeroBridge() public {
    vm.expectRevert(AggLayerReleaser.ZeroAddress.selector);
    new AggLayerReleaser(
      address(0), address(resource), L1_UNI, INITIAL_THRESHOLD, address(tokenJar)
    );
  }

  function test_revert_constructor_zeroL1Resource() public {
    vm.expectRevert(AggLayerReleaser.ZeroAddress.selector);
    new AggLayerReleaser(
      address(bridge), address(resource), address(0), INITIAL_THRESHOLD, address(tokenJar)
    );
  }

  /// @dev A token the bridge has never wrapped, e.g. X Layer's OptimismMintableERC20 UNI
  function test_revert_constructor_resourceUnknownToBridge() public {
    MockERC20 opUni = new MockERC20("Uniswap", "UNI", 18);
    vm.expectRevert(AggLayerReleaser.ResourceNotWrappedL1Resource.selector);
    new AggLayerReleaser(
      address(bridge), address(opUni), L1_UNI, INITIAL_THRESHOLD, address(tokenJar)
    );
  }

  function test_revert_constructor_resourceWrapsDifferentL1Token() public {
    MockERC20 other = new MockERC20("Other", "OTH", 18);
    bridge.setWrappedToken(address(other), ETHEREUM_NETWORK_ID, makeAddr("otherL1Token"));
    vm.expectRevert(AggLayerReleaser.ResourceNotWrappedL1Resource.selector);
    new AggLayerReleaser(
      address(bridge), address(other), L1_UNI, INITIAL_THRESHOLD, address(tokenJar)
    );
  }

  function test_revert_constructor_resourceWrapsNonEthereumToken() public {
    MockERC20 other = new MockERC20("Other", "OTH", 18);
    bridge.setWrappedToken(address(other), 1, L1_UNI);
    vm.expectRevert(AggLayerReleaser.ResourceNotWrappedL1Resource.selector);
    new AggLayerReleaser(
      address(bridge), address(other), L1_UNI, INITIAL_THRESHOLD, address(tokenJar)
    );
  }

  // ─── release ───

  function test_release_burnsWrappedResourceAndBridgesToEthereumBurnAddress() public {
    Currency[] memory assets = new Currency[](2);
    assets[0] = Currency.wrap(address(mockToken));
    assets[1] = Currency.wrap(address(0));

    uint256 supplyBefore = resource.totalSupply();
    uint256 nonceBefore = releaser.nonce();

    vm.startPrank(alice);
    resource.approve(address(releaser), INITIAL_THRESHOLD);

    vm.expectEmit(address(releaser));
    emit IReleaser.Released(nonceBefore, alice, assets);
    vm.expectEmit(address(bridge));
    emit IAggLayerBridge.BridgeEvent(
      0, ETHEREUM_NETWORK_ID, L1_UNI, ETHEREUM_NETWORK_ID, BURN_ADDRESS, INITIAL_THRESHOLD, "", 0
    );

    releaser.release(nonceBefore, assets, alice);
    vm.stopPrank();

    // Stage 1: fee assets released to the recipient
    assertEq(mockToken.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
    assertEq(alice.balance, INITIAL_NATIVE_AMOUNT);
    assertEq(mockToken.balanceOf(address(tokenJar)), 0);
    assertEq(address(tokenJar).balance, 0);

    // Stage 2: the bridge burned the wrapped resource held by the releaser
    assertEq(resource.balanceOf(alice), INITIAL_TOKEN_AMOUNT - INITIAL_THRESHOLD);
    assertEq(resource.balanceOf(address(releaser)), 0);
    assertEq(resource.balanceOf(address(bridge)), 0);
    assertEq(resource.totalSupply(), supplyBefore - INITIAL_THRESHOLD);
    assertEq(bridge.depositCount(), 1);

    assertEq(releaser.nonce(), nonceBefore + 1);
  }

  /// @dev On a sovereign chain that maps UNI to a token the bridge cannot mint, the bridge pulls
  /// through the allowance set in `_afterRelease` and escrows the tokens instead of burning
  function test_release_notMintableResourceIsEscrowedViaAllowance() public {
    bridge.setNotMintable(address(resource), true);

    Currency[] memory assets = new Currency[](1);
    assets[0] = Currency.wrap(address(mockToken));

    uint256 supplyBefore = resource.totalSupply();

    vm.startPrank(alice);
    resource.approve(address(releaser), INITIAL_THRESHOLD);
    releaser.release(releaser.nonce(), assets, alice);
    vm.stopPrank();

    assertEq(resource.balanceOf(address(releaser)), 0);
    assertEq(resource.balanceOf(address(bridge)), INITIAL_THRESHOLD);
    assertEq(resource.totalSupply(), supplyBefore);
    assertEq(resource.allowance(address(releaser), address(bridge)), 0);
  }

  /// @dev For a bridge-minted token the allowance is not consumed; it is bounded by `threshold`
  /// and overwritten on each release rather than accumulated
  function test_release_leftoverAllowanceIsBoundedByThreshold() public {
    Currency[] memory assets = new Currency[](1);
    assets[0] = Currency.wrap(address(mockToken));

    vm.startPrank(alice);
    resource.approve(address(releaser), INITIAL_THRESHOLD * 2);
    releaser.release(releaser.nonce(), assets, alice);
    assertEq(resource.allowance(address(releaser), address(bridge)), INITIAL_THRESHOLD);

    mockToken.mint(address(tokenJar), INITIAL_TOKEN_AMOUNT);
    releaser.release(releaser.nonce(), assets, alice);
    assertEq(resource.allowance(address(releaser), address(bridge)), INITIAL_THRESHOLD);
    vm.stopPrank();
  }

  function test_release_emptyAssetArrayStillBridges() public {
    Currency[] memory assets = new Currency[](0);
    uint256 supplyBefore = resource.totalSupply();

    vm.startPrank(alice);
    resource.approve(address(releaser), INITIAL_THRESHOLD);
    releaser.release(releaser.nonce(), assets, alice);
    vm.stopPrank();

    assertEq(resource.totalSupply(), supplyBefore - INITIAL_THRESHOLD);
    assertEq(bridge.depositCount(), 1);
  }

  function test_release_differentRecipient() public {
    Currency[] memory assets = new Currency[](1);
    assets[0] = Currency.wrap(address(mockToken));

    vm.startPrank(alice);
    resource.approve(address(releaser), INITIAL_THRESHOLD);
    releaser.release(releaser.nonce(), assets, bob);
    vm.stopPrank();

    assertEq(mockToken.balanceOf(bob), INITIAL_TOKEN_AMOUNT);
    assertEq(mockToken.balanceOf(alice), 0);
    assertEq(resource.balanceOf(alice), INITIAL_TOKEN_AMOUNT - INITIAL_THRESHOLD);
  }

  function test_fuzz_release_threshold(uint256 thresholdAmount) public {
    thresholdAmount = bound(thresholdAmount, 1, INITIAL_TOKEN_AMOUNT);

    vm.prank(thresholdSetter);
    releaser.setThreshold(thresholdAmount);

    Currency[] memory assets = new Currency[](1);
    assets[0] = Currency.wrap(address(mockToken));

    uint256 supplyBefore = resource.totalSupply();

    vm.startPrank(alice);
    resource.approve(address(releaser), thresholdAmount);

    vm.expectEmit(address(bridge));
    emit IAggLayerBridge.BridgeEvent(
      0, ETHEREUM_NETWORK_ID, L1_UNI, ETHEREUM_NETWORK_ID, BURN_ADDRESS, thresholdAmount, "", 0
    );

    releaser.release(releaser.nonce(), assets, alice);
    vm.stopPrank();

    assertEq(resource.totalSupply(), supplyBefore - thresholdAmount);
    assertEq(resource.balanceOf(alice), INITIAL_TOKEN_AMOUNT - thresholdAmount);
    assertEq(resource.balanceOf(address(releaser)), 0);
  }

  // ─── reverts ───

  function test_revert_release_insufficientApproval() public {
    Currency[] memory assets = new Currency[](1);
    assets[0] = Currency.wrap(address(mockToken));

    vm.startPrank(alice);
    resource.approve(address(releaser), INITIAL_THRESHOLD - 1);
    uint256 currentNonce = releaser.nonce();
    vm.expectRevert();
    releaser.release(currentNonce, assets, alice);
    vm.stopPrank();
  }

  function test_revert_release_wrongNonce() public {
    Currency[] memory assets = new Currency[](1);
    assets[0] = Currency.wrap(address(mockToken));

    vm.startPrank(alice);
    resource.approve(address(releaser), INITIAL_THRESHOLD);
    uint256 currentNonce = releaser.nonce();
    vm.expectRevert(INonce.InvalidNonce.selector);
    releaser.release(currentNonce + 1, assets, alice);
    vm.stopPrank();
  }

  function test_revert_release_tooManyAssets() public {
    Currency[] memory assets = new Currency[](releaser.MAX_RELEASE_LENGTH() + 1);
    for (uint256 i = 0; i < assets.length; i++) {
      assets[i] = Currency.wrap(address(mockToken));
    }

    vm.startPrank(alice);
    resource.approve(address(releaser), INITIAL_THRESHOLD);
    uint256 currentNonce = releaser.nonce();
    vm.expectRevert(IReleaser.TooManyAssets.selector);
    releaser.release(currentNonce, assets, alice);
    vm.stopPrank();
  }

  /// @dev The bridge call is atomic with the TokenJar release: if the bridge refuses (e.g.
  /// emergency state), no fee assets leave the jar and no resource leaves the caller
  function test_revert_release_bridgeInEmergencyState() public {
    bridge.setEmergencyState(true);

    Currency[] memory assets = new Currency[](1);
    assets[0] = Currency.wrap(address(mockToken));

    vm.startPrank(alice);
    resource.approve(address(releaser), INITIAL_THRESHOLD);
    uint256 currentNonce = releaser.nonce();
    vm.expectRevert(MockAggLayerBridge.OnlyNotEmergencyState.selector);
    releaser.release(currentNonce, assets, alice);
    vm.stopPrank();

    assertEq(mockToken.balanceOf(address(tokenJar)), INITIAL_TOKEN_AMOUNT);
    assertEq(resource.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
  }

  /// @dev The releaser has no `receive`, since the unified bridge takes no fee in the gas token
  function test_revert_sendingNativeToReleaser() public {
    vm.deal(alice, 1 ether);
    vm.prank(alice);
    (bool success,) = address(releaser).call{value: 1 ether}("");
    assertFalse(success);
  }
}
