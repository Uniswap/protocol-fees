// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {AssetSink, IAssetSink} from "../src/AssetSink.sol";
import {MockReleaser, MockRevertingReceiver} from "./mocks/MockReleaser.sol";

contract AssetSinkTest is Test {
  using CurrencyLibrary for Currency;

  IAssetSink public assetSink;
  MockReleaser public mockReleaser;
  MockRevertingReceiver public mockRevertingReceiver;
  MockERC20 public mockToken;

  address public owner = address(this);
  address public alice;
  address public bob;
  address public unauthorizedUser;

  uint256 public constant INITIAL_TOKEN_AMOUNT = 1000e18;
  uint256 public constant INITIAL_NATIVE_AMOUNT = 10 ether;

  function setUp() public {
    alice = makeAddr("alice");
    bob = makeAddr("bob");
    owner = makeAddr("owner");
    unauthorizedUser = makeAddr("unauthorizedUser");

    // Deploy mock contracts first
    mockToken = new MockERC20("MOCK", "MOCK", 18);
    mockRevertingReceiver = new MockRevertingReceiver();

    vm.startPrank(owner);
    assetSink = new AssetSink();
    mockReleaser = new MockReleaser(address(assetSink));
    assetSink.setReleaser(address(mockReleaser));
    vm.stopPrank();

    // Mint tokens and send to AssetSink
    mockToken.mint(address(assetSink), INITIAL_TOKEN_AMOUNT);

    // Send native tokens to AssetSink
    vm.deal(address(assetSink), INITIAL_NATIVE_AMOUNT);

    // Give test addresses some ETH
    vm.deal(alice, 100 ether);
    vm.deal(bob, 100 ether);
  }

  function test_Release_ERC20_Success() public {
    Currency asset = Currency.wrap(address(mockToken));
    uint256 initialBalance = asset.balanceOf(address(assetSink));

    // Use releaser contract to release assets
    mockReleaser.release(asset, alice);

    assertEq(mockToken.balanceOf(alice), initialBalance);
    assertEq(asset.balanceOf(address(assetSink)), 0);
  }

  function test_Release_ERC20_ZeroBalance() public {
    // Create new token with zero balance
    MockERC20 emptyToken = new MockERC20("Empty", "EMPTY", 18);
    Currency asset = Currency.wrap(address(emptyToken));

    // Should not emit event or revert
    mockReleaser.release(asset, alice);

    assertEq(emptyToken.balanceOf(alice), 0);
  }

  function test_Release_ERC20_OnlyReleaser() public {
    Currency[] memory asset = new Currency[](1);
    asset[0] = Currency.wrap(address(mockToken));
    // Direct call to AssetSink should fail - only releaser can call
    vm.expectRevert(IAssetSink.Unauthorized.selector);
    assetSink.release(asset, alice);
  }

  function test_Release_ERC20_ToZeroAddress() public {
    Currency asset = Currency.wrap(address(mockToken));
    mockReleaser.release(asset, address(0));
    assertEq(mockToken.balanceOf(address(0)), INITIAL_TOKEN_AMOUNT);
  }

  function test_Release_ERC20_MultipleCalls() public {
    Currency asset = Currency.wrap(address(mockToken));
    // First release
    mockReleaser.release(asset, alice);
    assertEq(mockToken.balanceOf(alice), INITIAL_TOKEN_AMOUNT);

    // Second release should do nothing
    mockReleaser.release(asset, alice);
    assertEq(mockToken.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
  }

  function test_Release_Native_Success() public {
    Currency nativeAsset = Currency.wrap(address(0));
    uint256 initialBalance = nativeAsset.balanceOf(address(assetSink));
    uint256 aliceInitialBalance = alice.balance;

    mockReleaser.release(nativeAsset, alice);

    assertEq(alice.balance, aliceInitialBalance + initialBalance);
    assertEq(nativeAsset.balanceOf(address(assetSink)), 0);
  }

  function test_Release_Native_ZeroBalance() public {
    Currency nativeAsset = Currency.wrap(address(0));
    // Drain the AssetSink first
    mockReleaser.release(nativeAsset, alice);

    // Should not emit event or revert
    mockReleaser.release(nativeAsset, alice);

    assertEq(nativeAsset.balanceOf(address(assetSink)), 0);
  }

  function test_Release_Native_OnlyReleaser() public {
    Currency[] memory nativeAsset = new Currency[](1);
    nativeAsset[0] = Currency.wrap(address(0));
    // Direct call to AssetSink should fail - only releaser can call
    vm.expectRevert(IAssetSink.Unauthorized.selector);
    assetSink.release(nativeAsset, alice);
  }

  function test_Release_Native_TransferFails() public {
    Currency nativeAsset = Currency.wrap(address(0));
    vm.expectRevert();
    mockReleaser.release(nativeAsset, address(mockRevertingReceiver));
  }

  function test_Release_ToCaller() public {
    Currency asset = Currency.wrap(address(mockToken));
    uint256 initialBalance = asset.balanceOf(address(assetSink));

    // Use releaseToCaller function - recipient is msg.sender
    vm.prank(alice);
    mockReleaser.releaseToCaller(asset);

    assertEq(mockToken.balanceOf(alice), initialBalance);
    assertEq(asset.balanceOf(address(assetSink)), 0);
  }

  function test_setReleaser() public {
    MockReleaser newReleaser = new MockReleaser(payable(address(assetSink)));
    vm.prank(owner);
    assetSink.setReleaser(address(newReleaser));
    assertEq(assetSink.releaser(), address(newReleaser));
  }

  function test_setReleaser_Unauthorized() public {
    MockReleaser newReleaser = new MockReleaser(payable(address(assetSink)));
    vm.expectRevert("UNAUTHORIZED");
    assetSink.setReleaser(address(newReleaser));

    assertEq(assetSink.releaser(), address(mockReleaser));
  }

  /*//////////////////////////////////////////////////////////////
                           FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

  function testFuzz_Release_ERC20_DifferentAmounts(uint256 amount) public {
    vm.assume(amount > 0 && amount <= type(uint128).max);

    // Create new token and mint specific amount
    MockERC20 fuzzToken = new MockERC20("FuzzToken", "FUZZ", 18);
    fuzzToken.mint(address(assetSink), amount);
    Currency asset = Currency.wrap(address(fuzzToken));

    mockReleaser.release(asset, alice);

    assertEq(fuzzToken.balanceOf(alice), amount);
    assertEq(asset.balanceOf(address(assetSink)), 0);
  }

  function testFuzz_Release_Native_DifferentAmounts(uint256 amount) public {
    vm.assume(amount > 0 && amount <= 1000 ether);

    // Create new AssetSink with releaser
    vm.startPrank(owner);
    AssetSink fuzzSink = new AssetSink();
    MockReleaser fuzzReleaser = new MockReleaser(address(fuzzSink));
    fuzzSink.setReleaser(address(fuzzReleaser));
    vm.stopPrank();

    vm.deal(address(fuzzSink), amount);
    Currency nativeAsset = Currency.wrap(address(0));

    uint256 aliceInitialBalance = alice.balance;
    fuzzReleaser.release(nativeAsset, alice);

    assertEq(alice.balance, aliceInitialBalance + amount);
    assertEq(address(fuzzSink).balance, 0);
  }

  function testFuzz_OnlyReleaser_DifferentCallers(address caller) public {
    vm.assume(caller != address(mockReleaser));

    Currency[] memory erc20Asset = new Currency[](1);
    erc20Asset[0] = Currency.wrap(address(mockToken));

    Currency[] memory nativeAsset = new Currency[](1);
    nativeAsset[0] = Currency.wrap(address(0));

    vm.prank(caller);
    vm.expectRevert(IAssetSink.Unauthorized.selector);
    assetSink.release(erc20Asset, alice);

    vm.prank(caller);
    vm.expectRevert(IAssetSink.Unauthorized.selector);
    assetSink.release(nativeAsset, alice);
  }
}
