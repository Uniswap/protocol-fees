// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {ArbitrumBridgedResourceFirepit} from "../src/releasers/ArbitrumBridgedResourceFirepit.sol";
import {TokenJar, ITokenJar} from "../src/TokenJar.sol";
import {INonce} from "../src/interfaces/base/INonce.sol";
import {IResourceManager} from "../src/interfaces/base/IResourceManager.sol";
import {IL2GatewayRouter} from "../src/interfaces/external/IL2GatewayRouter.sol";

// Mock L2GatewayRouter for testing
contract MockL2GatewayRouter is IL2GatewayRouter {
  address public mockGateway;

  event OutboundTransfer(address indexed l1Token, address indexed to, uint256 amount, bytes data);

  constructor(address _mockGateway) {
    mockGateway = _mockGateway;
  }

  function outboundTransfer(address _l1Token, address _to, uint256 _amount, bytes calldata _data)
    external
    payable
    override
    returns (bytes memory)
  {
    // Pull tokens from the caller to simulate the gateway taking custody
    // In reality, the router delegates to the gateway, but for testing we simplify
    // We need to get the L2 token from the firepit
    ArbitrumBridgedResourceFirepit firepit = ArbitrumBridgedResourceFirepit(msg.sender);
    MockERC20(address(firepit.RESOURCE())).transferFrom(msg.sender, address(this), _amount);

    emit OutboundTransfer(_l1Token, _to, _amount, _data);
    return abi.encode(uint256(1)); // Return a mock withdrawal ID
  }

  function getGateway(address) external view override returns (address) {
    return mockGateway;
  }

  function calculateL2TokenAddress(address) external pure override returns (address) {
    return address(0);
  }
}

// Mock Gateway for token approval
contract MockGateway {
  // Just needs to exist for approval testing

  }

// Concrete implementation for testing
contract TestArbitrumBridgedResourceFirepit is ArbitrumBridgedResourceFirepit {
  constructor(address _resource, address _l1Resource, uint256 _threshold, address _tokenJar)
    ArbitrumBridgedResourceFirepit(_resource, _l1Resource, _threshold, _tokenJar)
  {
    // Additional approval for the mock router (since it pulls tokens directly in tests)
    MockERC20(_resource).approve(L2_GATEWAY_ROUTER, type(uint256).max);
  }
}

contract ArbitrumBridgedResourceFirepitTest is Test {
  TestArbitrumBridgedResourceFirepit internal firepit;
  TokenJar internal tokenJar;
  MockERC20 internal resource;
  MockERC20 internal mockToken;
  MockL2GatewayRouter internal mockRouter;
  MockGateway internal mockGateway;

  address internal alice = makeAddr("alice");
  address internal bob = makeAddr("bob");
  address internal thresholdSetter = makeAddr("thresholdSetter");

  address internal constant L1_UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
  uint256 internal constant INITIAL_THRESHOLD = 100e18;
  uint256 internal constant INITIAL_TOKEN_AMOUNT = 1000e18;
  uint256 internal constant INITIAL_NATIVE_AMOUNT = 10 ether;

  function setUp() public {
    // Deploy mock gateway first
    mockGateway = new MockGateway();

    // Deploy mock router
    mockRouter = new MockL2GatewayRouter(address(mockGateway));

    // Deploy mock router at the expected address
    vm.etch(
      0x5288c571Fd7aD117beA99bF60FE0846C4E84F933, // L2_GATEWAY_ROUTER
      address(mockRouter).code
    );
    // Store the mockGateway address in the router's storage slot
    vm.store(
      0x5288c571Fd7aD117beA99bF60FE0846C4E84F933,
      bytes32(uint256(0)), // First storage slot for mockGateway
      bytes32(uint256(uint160(address(mockGateway))))
    );

    // Deploy resource token
    resource = new MockERC20("Bridged UNI", "UNI", 18);
    mockToken = new MockERC20("MockToken", "MTK", 18);

    // Deploy tokenJar
    tokenJar = new TokenJar();

    // Deploy ArbitrumBridgedResourceFirepit
    firepit = new TestArbitrumBridgedResourceFirepit(
      address(resource), L1_UNI, INITIAL_THRESHOLD, address(tokenJar)
    );

    // Set up permissions
    firepit.setThresholdSetter(thresholdSetter);
    tokenJar.setReleaser(address(firepit));

    // Mint tokens to users and tokenJar
    resource.mint(alice, INITIAL_TOKEN_AMOUNT);
    resource.mint(bob, INITIAL_TOKEN_AMOUNT);
    mockToken.mint(address(tokenJar), INITIAL_TOKEN_AMOUNT);

    // Give native currency to tokenJar
    vm.deal(address(tokenJar), INITIAL_NATIVE_AMOUNT);
    vm.deal(alice, INITIAL_NATIVE_AMOUNT);
    vm.deal(bob, INITIAL_NATIVE_AMOUNT);
  }

  function test_constructor() public view {
    assertEq(address(firepit.RESOURCE()), address(resource));
    assertEq(firepit.RESOURCE_RECIPIENT(), address(firepit));
    assertEq(firepit.threshold(), INITIAL_THRESHOLD);
    assertEq(address(firepit.TOKEN_JAR()), address(tokenJar));
    assertEq(firepit.owner(), address(this));
    assertEq(firepit.nonce(), 0);
    assertEq(firepit.L1_RESOURCE(), L1_UNI);
  }

  function test_l2GatewayRouterConstant() public view {
    assertEq(firepit.L2_GATEWAY_ROUTER(), 0x5288c571Fd7aD117beA99bF60FE0846C4E84F933);
  }

  function test_release_successfulTokenRelease() public {
    uint256 aliceResourceBefore = resource.balanceOf(alice);
    uint256 aliceTokenBefore = mockToken.balanceOf(alice);
    uint256 nonceBefore = firepit.nonce();

    vm.startPrank(alice);
    resource.approve(address(firepit), INITIAL_THRESHOLD);

    Currency[] memory releaseTokens = new Currency[](1);
    releaseTokens[0] = Currency.wrap(address(mockToken));

    // Expect the OutboundTransfer event from the router
    vm.expectEmit(true, true, false, true, firepit.L2_GATEWAY_ROUTER());
    emit MockL2GatewayRouter.OutboundTransfer(L1_UNI, address(0xdead), INITIAL_THRESHOLD, "");

    firepit.release(nonceBefore, releaseTokens, alice);
    vm.stopPrank();

    // Check resource was transferred from alice to router (simulating gateway)
    assertEq(resource.balanceOf(alice), aliceResourceBefore - INITIAL_THRESHOLD);
    assertEq(resource.balanceOf(address(firepit)), 0);
    assertEq(resource.balanceOf(firepit.L2_GATEWAY_ROUTER()), INITIAL_THRESHOLD);

    // Check mock token was released to alice
    assertEq(mockToken.balanceOf(alice), aliceTokenBefore + INITIAL_TOKEN_AMOUNT);
    assertEq(mockToken.balanceOf(address(tokenJar)), 0);

    // Check nonce was incremented
    assertEq(firepit.nonce(), nonceBefore + 1);
  }

  function test_release_successfulNativeRelease() public {
    uint256 bobNativeBefore = bob.balance;
    uint256 tokenJarNativeBefore = address(tokenJar).balance;
    uint256 nonceBefore = firepit.nonce();

    vm.startPrank(bob);
    resource.approve(address(firepit), INITIAL_THRESHOLD);

    Currency[] memory releaseNative = new Currency[](1);
    releaseNative[0] = CurrencyLibrary.ADDRESS_ZERO;
    firepit.release(nonceBefore, releaseNative, bob);
    vm.stopPrank();

    // Check native currency was released
    assertEq(bob.balance, bobNativeBefore + tokenJarNativeBefore);
    assertEq(address(tokenJar).balance, 0);

    // Check nonce was incremented
    assertEq(firepit.nonce(), nonceBefore + 1);
  }

  function test_release_successfulMultiAssetRelease() public {
    uint256 aliceTokenBefore = mockToken.balanceOf(alice);
    uint256 aliceNativeBefore = alice.balance;
    uint256 tokenJarNativeBefore = address(tokenJar).balance;
    uint256 nonceBefore = firepit.nonce();

    vm.startPrank(alice);
    resource.approve(address(firepit), INITIAL_THRESHOLD);

    Currency[] memory releaseBoth = new Currency[](2);
    releaseBoth[0] = Currency.wrap(address(mockToken));
    releaseBoth[1] = CurrencyLibrary.ADDRESS_ZERO;
    firepit.release(nonceBefore, releaseBoth, alice);
    vm.stopPrank();

    // Check both token and native were released
    assertEq(mockToken.balanceOf(alice), aliceTokenBefore + INITIAL_TOKEN_AMOUNT);
    assertEq(alice.balance, aliceNativeBefore + tokenJarNativeBefore);
    assertEq(mockToken.balanceOf(address(tokenJar)), 0);
    assertEq(address(tokenJar).balance, 0);

    // Check nonce was incremented
    assertEq(firepit.nonce(), nonceBefore + 1);
  }

  function test_revert_release_invalidNonce() public {
    vm.startPrank(alice);
    resource.approve(address(firepit), INITIAL_THRESHOLD);

    Currency[] memory releaseTokens = new Currency[](1);
    releaseTokens[0] = Currency.wrap(address(mockToken));
    uint256 wrongNonce = firepit.nonce() + 1;
    vm.expectRevert(INonce.InvalidNonce.selector);
    firepit.release(wrongNonce, releaseTokens, alice);
    vm.stopPrank();
  }

  function test_revert_release_insufficientResourceBalance() public {
    // Transfer most of alice's resources away
    vm.prank(alice);
    resource.transfer(bob, INITIAL_TOKEN_AMOUNT - 50e18);

    vm.startPrank(alice);
    resource.approve(address(firepit), INITIAL_THRESHOLD);

    Currency[] memory releaseTokens = new Currency[](1);
    releaseTokens[0] = Currency.wrap(address(mockToken));
    vm.expectRevert(address(resource));
    firepit.release(0, releaseTokens, alice);
    vm.stopPrank();
  }

  function test_revert_release_insufficientAllowance() public {
    vm.startPrank(alice);
    resource.approve(address(firepit), INITIAL_THRESHOLD - 1);

    Currency[] memory releaseTokens = new Currency[](1);
    releaseTokens[0] = Currency.wrap(address(mockToken));
    vm.expectRevert(address(resource));
    firepit.release(0, releaseTokens, alice);
    vm.stopPrank();
  }

  function test_setThreshold() public {
    uint256 newThreshold = 200e18;

    vm.prank(thresholdSetter);
    firepit.setThreshold(newThreshold);

    assertEq(firepit.threshold(), newThreshold);

    Currency[] memory releaseTokens = new Currency[](1);
    releaseTokens[0] = Currency.wrap(address(mockToken));

    // Test release with new threshold
    vm.startPrank(alice);
    resource.approve(address(firepit), newThreshold);

    // Expect the OutboundTransfer event with new threshold amount
    vm.expectEmit(true, true, false, true, firepit.L2_GATEWAY_ROUTER());
    emit MockL2GatewayRouter.OutboundTransfer(L1_UNI, address(0xdead), newThreshold, "");

    firepit.release(firepit.nonce(), releaseTokens, alice);
    vm.stopPrank();

    // Check correct amount was withdrawn to router
    assertEq(resource.balanceOf(firepit.L2_GATEWAY_ROUTER()), newThreshold);
  }

  function test_revert_setThreshold_notThresholdSetter() public {
    uint256 newThreshold = 200e18;

    vm.expectRevert(IResourceManager.Unauthorized.selector);
    vm.prank(alice);
    firepit.setThreshold(newThreshold);

    vm.expectRevert(IResourceManager.Unauthorized.selector);
    vm.prank(bob);
    firepit.setThreshold(newThreshold);
  }

  function test_setThresholdSetter() public {
    address newSetter = makeAddr("newSetter");

    vm.prank(firepit.owner());
    firepit.setThresholdSetter(newSetter);

    assertEq(firepit.thresholdSetter(), newSetter);

    // Test that new setter can set threshold
    uint256 newThreshold = 300e18;
    vm.prank(newSetter);
    firepit.setThreshold(newThreshold);
    assertEq(firepit.threshold(), newThreshold);
  }

  function test_revert_setThresholdSetter_notOwner() public {
    address newSetter = makeAddr("newSetter");

    vm.expectRevert();
    vm.prank(alice);
    firepit.setThresholdSetter(newSetter);
  }

  function test_release_nonceIncrement() public {
    uint256 initialNonce = firepit.nonce();

    Currency[] memory releaseTokens = new Currency[](1);
    releaseTokens[0] = Currency.wrap(address(mockToken));

    // First release
    vm.startPrank(alice);
    resource.approve(address(firepit), INITIAL_THRESHOLD * 3);
    firepit.release(initialNonce, releaseTokens, alice);
    assertEq(firepit.nonce(), initialNonce + 1);

    // Mint more tokens to tokenJar
    mockToken.mint(address(tokenJar), INITIAL_TOKEN_AMOUNT);

    // Second release with incremented nonce
    firepit.release(initialNonce + 1, releaseTokens, alice);
    assertEq(firepit.nonce(), initialNonce + 2);

    // Mint more tokens to tokenJar
    mockToken.mint(address(tokenJar), INITIAL_TOKEN_AMOUNT);

    // Third release
    firepit.release(initialNonce + 2, releaseTokens, alice);
    assertEq(firepit.nonce(), initialNonce + 3);
    vm.stopPrank();
  }

  function test_revert_release_reusedNonce() public {
    uint256 currentNonce = firepit.nonce();

    Currency[] memory releaseTokens = new Currency[](1);
    releaseTokens[0] = Currency.wrap(address(mockToken));

    // First release succeeds
    vm.startPrank(alice);
    resource.approve(address(firepit), INITIAL_THRESHOLD * 2);
    firepit.release(currentNonce, releaseTokens, alice);

    // Second release with same nonce fails
    vm.expectRevert(INonce.InvalidNonce.selector);
    firepit.release(currentNonce, releaseTokens, alice);
    vm.stopPrank();
  }

  function test_release_differentRecipients() public {
    uint256 nonceBefore = firepit.nonce();

    Currency[] memory releaseTokens = new Currency[](1);
    releaseTokens[0] = Currency.wrap(address(mockToken));

    // Alice initiates release to bob
    vm.startPrank(alice);
    resource.approve(address(firepit), INITIAL_THRESHOLD);
    firepit.release(nonceBefore, releaseTokens, bob);
    vm.stopPrank();

    // Check bob received the tokens
    assertEq(mockToken.balanceOf(bob), INITIAL_TOKEN_AMOUNT);
    assertEq(mockToken.balanceOf(alice), 0);
  }

  function test_fuzz_release_threshold(uint256 thresholdAmount) public {
    thresholdAmount = bound(thresholdAmount, 1e18, INITIAL_TOKEN_AMOUNT);

    // Set new threshold
    vm.prank(thresholdSetter);
    firepit.setThreshold(thresholdAmount);

    Currency[] memory releaseTokens = new Currency[](1);
    releaseTokens[0] = Currency.wrap(address(mockToken));

    // Execute release
    vm.startPrank(alice);
    resource.approve(address(firepit), thresholdAmount);

    // Expect the OutboundTransfer event with the fuzzed threshold amount
    vm.expectEmit(true, true, false, true, firepit.L2_GATEWAY_ROUTER());
    emit MockL2GatewayRouter.OutboundTransfer(L1_UNI, address(0xdead), thresholdAmount, "");

    firepit.release(firepit.nonce(), releaseTokens, alice);
    vm.stopPrank();

    // Verify correct amount was withdrawn to router
    assertEq(resource.balanceOf(firepit.L2_GATEWAY_ROUTER()), thresholdAmount);
    assertEq(resource.balanceOf(alice), INITIAL_TOKEN_AMOUNT - thresholdAmount);
  }

  function test_fuzz_release_multipleAssets(uint8 numAssets) public {
    numAssets = uint8(bound(numAssets, 1, 10));

    Currency[] memory assets = new Currency[](numAssets);
    MockERC20[] memory tokens = new MockERC20[](numAssets);

    // Create and fund multiple tokens
    for (uint8 i = 0; i < numAssets; i++) {
      tokens[i] = new MockERC20(
        string.concat("Token", vm.toString(i)), string.concat("TK", vm.toString(i)), 18
      );
      tokens[i].mint(address(tokenJar), INITIAL_TOKEN_AMOUNT);
      assets[i] = Currency.wrap(address(tokens[i]));
    }

    // Release all assets
    vm.startPrank(alice);
    resource.approve(address(firepit), INITIAL_THRESHOLD);
    firepit.release(firepit.nonce(), assets, alice);
    vm.stopPrank();

    // Verify all tokens were released
    for (uint8 i = 0; i < numAssets; i++) {
      assertEq(tokens[i].balanceOf(alice), INITIAL_TOKEN_AMOUNT);
      assertEq(tokens[i].balanceOf(address(tokenJar)), 0);
    }
  }

  function test_release_emptyAssetArray() public {
    Currency[] memory emptyAssets = new Currency[](0);
    uint256 nonceBefore = firepit.nonce();

    vm.startPrank(alice);
    resource.approve(address(firepit), INITIAL_THRESHOLD);

    // Expect the OutboundTransfer event even with empty assets array
    vm.expectEmit(true, true, false, true, firepit.L2_GATEWAY_ROUTER());
    emit MockL2GatewayRouter.OutboundTransfer(L1_UNI, address(0xdead), INITIAL_THRESHOLD, "");

    firepit.release(nonceBefore, emptyAssets, alice);
    vm.stopPrank();

    // Check resource was still transferred to router
    assertEq(resource.balanceOf(alice), INITIAL_TOKEN_AMOUNT - INITIAL_THRESHOLD);
    assertEq(resource.balanceOf(firepit.L2_GATEWAY_ROUTER()), INITIAL_THRESHOLD);

    // Check nonce was incremented
    assertEq(firepit.nonce(), nonceBefore + 1);
  }
}
