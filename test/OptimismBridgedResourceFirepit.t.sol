// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {Predeploys} from "@eth-optimism-bedrock/src/libraries/Predeploys.sol";

import {OptimismBridgedResourceFirepit} from "../src/releasers/OptimismBridgedResourceFirepit.sol";
import {TokenJar, ITokenJar} from "../src/TokenJar.sol";
import {INonce} from "../src/interfaces/base/INonce.sol";
import {IResourceManager} from "../src/interfaces/base/IResourceManager.sol";
import {IL2StandardBridge} from "../src/interfaces/external/IL2StandardBridge.sol";

// Concrete implementation of abstract OptimismBridgedResourceFirepit for testing
contract TestOptimismBridgedResourceFirepit is OptimismBridgedResourceFirepit {
  constructor(address _resource, uint256 _threshold, address _tokenJar)
    OptimismBridgedResourceFirepit(_resource, _threshold, _tokenJar)
  {
    // Approve the L2 Standard Bridge to transfer our resource tokens
    // Note on real OP stack chains with OptimismMintableERC20, this approval would not be needed
    MockERC20(_resource).approve(Predeploys.L2_STANDARD_BRIDGE, type(uint256).max);
  }
}

// Mock L2StandardBridge for testing
contract MockL2StandardBridge is IL2StandardBridge {
  event Withdrawn(
    address indexed l2Token,
    address indexed from,
    address indexed to,
    uint256 amount,
    uint32 minGasLimit,
    bytes extraData
  );

  function bridgeETHTo(address, uint32, bytes calldata) external payable override {
    revert("Not implemented");
  }

  function withdrawTo(
    address _l2Token,
    address _to,
    uint256 _amount,
    uint32 _minGasLimit,
    bytes calldata _extraData
  ) external override {
    // Pull tokens from the caller (OptimismBridgedResourceFirepit) to simulate the bridge taking
    // custody
    MockERC20(_l2Token).transferFrom(msg.sender, address(this), _amount);

    // Emit event to signal withdrawal initiation (in real bridge, this would trigger L1 processing)
    emit Withdrawn(_l2Token, msg.sender, _to, _amount, _minGasLimit, _extraData);
  }
}

contract OptimismBridgedResourceFirepitTest is Test {
  TestOptimismBridgedResourceFirepit internal firepit;
  TokenJar internal tokenJar;
  MockERC20 internal resource;
  MockERC20 internal mockToken;
  MockL2StandardBridge internal mockBridge;

  address internal alice = makeAddr("alice");
  address internal bob = makeAddr("bob");
  address internal thresholdSetter = makeAddr("thresholdSetter");

  uint256 internal constant INITIAL_THRESHOLD = 100e18;
  uint256 internal constant INITIAL_TOKEN_AMOUNT = 1000e18;
  uint256 internal constant INITIAL_NATIVE_AMOUNT = 10 ether;

  function setUp() public {
    // Deploy resource token
    resource = new MockERC20("Resource", "RSC", 18);
    mockToken = new MockERC20("MockToken", "MTK", 18);

    // Deploy mock L2 bridge at the expected predeploy address
    mockBridge = new MockL2StandardBridge();
    vm.etch(Predeploys.L2_STANDARD_BRIDGE, address(mockBridge).code);

    // Deploy tokenJar (no prank needed - deployer is the test contract)
    tokenJar = new TokenJar();

    // Deploy OptimismBridgedResourceFirepit (deployer is the test contract, becomes owner)
    firepit = new TestOptimismBridgedResourceFirepit(
      address(resource), INITIAL_THRESHOLD, address(tokenJar)
    );

    // Set up permissions
    firepit.setThresholdSetter(thresholdSetter); // test contract is owner
    tokenJar.setReleaser(address(firepit)); // test contract is owner

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
  }

  function test_release_successfulTokenRelease() public {
    uint256 aliceResourceBefore = resource.balanceOf(alice);
    uint256 aliceTokenBefore = mockToken.balanceOf(alice);
    uint256 nonceBefore = firepit.nonce();

    vm.startPrank(alice);
    resource.approve(address(firepit), INITIAL_THRESHOLD);

    Currency[] memory releaseTokens = new Currency[](1);
    releaseTokens[0] = Currency.wrap(address(mockToken));

    // Expect the Withdrawn event from the bridge
    vm.expectEmit(true, true, true, true, Predeploys.L2_STANDARD_BRIDGE);
    emit MockL2StandardBridge.Withdrawn(
      address(resource), address(firepit), address(0xdead), INITIAL_THRESHOLD, 100_000, ""
    );

    firepit.release(nonceBefore, releaseTokens, alice);
    vm.stopPrank();

    // Check resource was transferred from alice to bridge
    assertEq(resource.balanceOf(alice), aliceResourceBefore - INITIAL_THRESHOLD);
    assertEq(resource.balanceOf(address(firepit)), 0);
    assertEq(resource.balanceOf(Predeploys.L2_STANDARD_BRIDGE), INITIAL_THRESHOLD);

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

    // Expect the Withdrawn event with new threshold amount
    vm.expectEmit(true, true, true, true, Predeploys.L2_STANDARD_BRIDGE);
    emit MockL2StandardBridge.Withdrawn(
      address(resource), address(firepit), address(0xdead), newThreshold, 100_000, ""
    );

    firepit.release(firepit.nonce(), releaseTokens, alice);
    vm.stopPrank();

    // Check correct amount was withdrawn to bridge
    assertEq(resource.balanceOf(Predeploys.L2_STANDARD_BRIDGE), newThreshold);
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

    // Mint more tokens to alice
    mockToken.mint(address(tokenJar), INITIAL_TOKEN_AMOUNT);

    // Second release with incremented nonce
    firepit.release(initialNonce + 1, releaseTokens, alice);
    assertEq(firepit.nonce(), initialNonce + 2);

    // Mint more tokens to alice
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

    // Expect the Withdrawn event with the fuzzed threshold amount
    vm.expectEmit(true, true, true, true, Predeploys.L2_STANDARD_BRIDGE);
    emit MockL2StandardBridge.Withdrawn(
      address(resource), address(firepit), address(0xdead), thresholdAmount, 100_000, ""
    );

    firepit.release(firepit.nonce(), releaseTokens, alice);
    vm.stopPrank();

    // Verify correct amount was withdrawn to bridge
    assertEq(resource.balanceOf(Predeploys.L2_STANDARD_BRIDGE), thresholdAmount);
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

    // Expect the Withdrawn event even with empty assets array
    vm.expectEmit(true, true, true, true, Predeploys.L2_STANDARD_BRIDGE);
    emit MockL2StandardBridge.Withdrawn(
      address(resource), address(firepit), address(0xdead), INITIAL_THRESHOLD, 100_000, ""
    );

    firepit.release(nonceBefore, emptyAssets, alice);
    vm.stopPrank();

    // Check resource was still transferred to bridge
    assertEq(resource.balanceOf(alice), INITIAL_TOKEN_AMOUNT - INITIAL_THRESHOLD);
    assertEq(resource.balanceOf(Predeploys.L2_STANDARD_BRIDGE), INITIAL_THRESHOLD);

    // Check nonce was incremented
    assertEq(firepit.nonce(), nonceBefore + 1);
  }
}
