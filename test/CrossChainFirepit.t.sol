// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {PhoenixTestBase, FirepitDestination} from "./utils/PhoenixTestBase.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {INonce} from "../src/interfaces/base/INonce.sol";

contract CrossChainFirepitTest is PhoenixTestBase {
  uint32 public constant L2_GAS_LIMIT = 1_000_000;

  function setUp() public override {
    super.setUp();

    vm.prank(owner);
    assetSink.setReleaser(address(firepitDestination));
  }

  function test_release_release_erc20() public {
    assertEq(resource.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
    assertEq(resource.balanceOf(address(opStackFirepitSource)), 0);
    assertEq(resource.balanceOf(address(0xdead)), 0);

    vm.startPrank(alice);
    resource.approve(address(opStackFirepitSource), INITIAL_TOKEN_AMOUNT);
    opStackFirepitSource.release(
      opStackFirepitSource.nonce(), releaseMockToken, alice, L2_GAS_LIMIT
    );
    vm.stopPrank();

    assertEq(mockToken.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
    assertEq(mockToken.balanceOf(address(assetSink)), 0);
    assertEq(resource.balanceOf(alice), 0);
    assertEq(resource.balanceOf(address(opStackFirepitSource)), 0);
    assertEq(resource.balanceOf(address(0xdead)), opStackFirepitSource.threshold());
  }

  /// @dev release SUCCEEDS on reverting tokens
  function test_release_release_revertingToken() public {
    uint256 nonce = opStackFirepitSource.nonce();
    vm.startPrank(alice);
    resource.approve(address(opStackFirepitSource), INITIAL_TOKEN_AMOUNT);

    vm.expectEmit(true, true, false, false);
    emit FirepitDestination.FailedRelease(nonce, alice);
    opStackFirepitSource.release(nonce, releaseMockReverting, alice, L2_GAS_LIMIT);
    vm.stopPrank();

    // resource still burned
    assertEq(resource.balanceOf(alice), 0);
    assertEq(resource.balanceOf(address(opStackFirepitSource)), 0);
    assertEq(resource.balanceOf(address(0xdead)), opStackFirepitSource.threshold());

    // alice did NOT receive the reverting token
    assertEq(revertingToken.balanceOf(alice), 0);
  }

  /// @dev release SUCCEEDS on *releasing* an insufficient balance
  /// @dev note release FAILS on an insufficient balance of the RESOURCE token
  function test_release_release_insufficientBalance() public {
    Currency[] memory assets = new Currency[](1);
    assets[0] = Currency.wrap(address(0xffdeadbeefc0ffeebabeff));

    uint256 nonce = opStackFirepitSource.nonce();

    vm.startPrank(alice);
    resource.approve(address(opStackFirepitSource), INITIAL_TOKEN_AMOUNT);
    vm.expectEmit(true, true, false, false);
    emit FirepitDestination.FailedRelease(nonce, alice);
    opStackFirepitSource.release(nonce, assets, alice, L2_GAS_LIMIT);
    vm.stopPrank();

    // resource still burned
    assertEq(resource.balanceOf(alice), 0);
    assertEq(resource.balanceOf(address(opStackFirepitSource)), 0);
    assertEq(resource.balanceOf(address(0xdead)), opStackFirepitSource.threshold());
  }

  function test_release_release_native() public {
    uint256 bobNativeBefore = CurrencyLibrary.ADDRESS_ZERO.balanceOf(bob);
    uint256 assetSinkNativeBefore = CurrencyLibrary.ADDRESS_ZERO.balanceOf(address(assetSink));

    assertGt(assetSinkNativeBefore, 0);
    assertEq(resource.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
    assertEq(resource.balanceOf(address(opStackFirepitSource)), 0);
    assertEq(resource.balanceOf(address(0xdead)), 0);

    vm.startPrank(alice);
    resource.approve(address(opStackFirepitSource), INITIAL_TOKEN_AMOUNT);
    opStackFirepitSource.release(opStackFirepitSource.nonce(), releaseMockNative, bob, L2_GAS_LIMIT);
    vm.stopPrank();

    // resource burned
    assertEq(resource.balanceOf(alice), 0);
    assertEq(resource.balanceOf(address(opStackFirepitSource)), 0);
    assertEq(resource.balanceOf(address(0xdead)), opStackFirepitSource.threshold());

    // bob received native asset
    assertEq(CurrencyLibrary.ADDRESS_ZERO.balanceOf(bob), bobNativeBefore + assetSinkNativeBefore);
    assertEq(CurrencyLibrary.ADDRESS_ZERO.balanceOf(address(assetSink)), 0);
  }

  function test_release_release_OOGToken() public {
    uint256 currentNonce = opStackFirepitSource.nonce();
    uint256 currentDestinationNonce = firepitDestination.nonce();

    vm.startPrank(alice);
    resource.approve(address(opStackFirepitSource), INITIAL_TOKEN_AMOUNT);

    vm.expectEmit(true, true, false, false);
    emit FirepitDestination.FailedRelease(currentNonce, alice);
    opStackFirepitSource.release(opStackFirepitSource.nonce(), releaseMockOOG, alice, L2_GAS_LIMIT);
    vm.stopPrank();

    // resource still burned
    assertEq(resource.balanceOf(alice), 0);
    assertEq(resource.balanceOf(address(opStackFirepitSource)), 0);
    assertEq(resource.balanceOf(address(0xdead)), opStackFirepitSource.threshold());

    // nonces should have been incremented
    uint256 newNonce = opStackFirepitSource.nonce();
    uint256 newDestinationNonce = firepitDestination.nonce();
    assertEq(newNonce, currentNonce + 1);
    assertEq(newDestinationNonce, currentDestinationNonce + 1);
  }

  /// @dev insufficient balance of the RESOURCE token will lead to a revert
  function test_fuzz_revert_release_insufficient_balance(uint256 amount, uint256 seed) public {
    amount = bound(amount, 1, resource.balanceOf(alice));

    // alice spends some of her resource and is below the threshold
    vm.prank(alice);
    bool success = resource.transfer(bob, amount);
    assertTrue(success);

    // alice does not have the threshold amount
    assertLt(resource.balanceOf(alice), opStackFirepitSource.threshold());

    uint256 _nonce = opStackFirepitSource.nonce();

    vm.startPrank(alice);
    resource.approve(address(opStackFirepitSource), INITIAL_TOKEN_AMOUNT);
    vm.expectRevert();
    opStackFirepitSource.release(
      _nonce, fuzzReleaseAny[seed % fuzzReleaseAny.length], bob, L2_GAS_LIMIT
    );
    vm.stopPrank();
  }

  function test_fuzz_revert_release_invalid_nonce(uint256 _nonce, uint256 seed) public {
    vm.assume(_nonce != opStackFirepitSource.nonce());

    vm.startPrank(alice);
    resource.approve(address(opStackFirepitSource), INITIAL_TOKEN_AMOUNT);
    vm.expectRevert(INonce.InvalidNonce.selector);
    opStackFirepitSource.release(
      _nonce, fuzzReleaseAny[seed % fuzzReleaseAny.length], bob, L2_GAS_LIMIT
    );
    vm.stopPrank();
  }

  /// @dev test that two transactions with the same nonce, the second one should revert
  function test_revert_release_frontrun() public {
    uint256 _nonce = opStackFirepitSource.nonce();

    vm.startPrank(alice);
    resource.approve(address(opStackFirepitSource), INITIAL_TOKEN_AMOUNT);
    opStackFirepitSource.release(_nonce, releaseMockBoth, alice, L2_GAS_LIMIT);
    vm.stopPrank();

    vm.startPrank(bob);
    resource.approve(address(opStackFirepitSource), INITIAL_TOKEN_AMOUNT);
    vm.expectRevert(INonce.InvalidNonce.selector);
    opStackFirepitSource.release(_nonce, releaseMockBoth, bob, L2_GAS_LIMIT);
    vm.stopPrank();
  }

  /// @dev test that insufficient gas DOES NOT revert
  function test_fuzz_release_insufficient_gas(uint8 seed) public {
    uint256 currentNonce = opStackFirepitSource.nonce();
    uint256 currentDestinationNonce = firepitDestination.nonce();

    TestBalances memory aliceBalances = _testBalances(alice);

    vm.startPrank(alice);
    resource.approve(address(opStackFirepitSource), INITIAL_TOKEN_AMOUNT);
    vm.expectEmit(false, false, false, false, address(firepitDestination), 1);
    emit FirepitDestination.FailedRelease(0, address(0));
    opStackFirepitSource.release{gas: 150_000}(
      currentNonce, fuzzReleaseAny[seed % fuzzReleaseAny.length], alice, 150_000
    );
    vm.stopPrank();

    // alice did not receive any assets
    TestBalances memory aliceBalancesAfter = _testBalances(alice);
    assertEq(aliceBalancesAfter.native, aliceBalances.native);
    assertEq(aliceBalancesAfter.mockToken, aliceBalances.mockToken);

    // nonces should have been incremented
    uint256 newNonce = opStackFirepitSource.nonce();
    uint256 newDestinationNonce = firepitDestination.nonce();
    assertEq(newNonce, currentNonce + 1);
    assertEq(newDestinationNonce, currentDestinationNonce + 1);
  }

  /// @dev releasing a revert token, OOG token, or revert bomb token are still successful
  function test_fuzz_gas_release_malicious(uint32 gasUsed, uint32 revertLength) public {
    vm.assume(150_000 < gasUsed);
    try revertBombToken.setBigReason(revertLength) {} catch {}

    uint256 currentNonce = opStackFirepitSource.nonce();
    uint256 currentDestinationNonce = firepitDestination.nonce();

    // the cross-chain message always succeeds
    vm.startPrank(alice);
    resource.approve(address(opStackFirepitSource), INITIAL_TOKEN_AMOUNT);
    opStackFirepitSource.release{gas: gasUsed}(currentNonce, releaseMalicious, alice, gasUsed);
    vm.stopPrank();

    // nonces should have been incremented
    uint256 newNonce = opStackFirepitSource.nonce();
    uint256 newDestinationNonce = firepitDestination.nonce();
    assertEq(newNonce, currentNonce + 1);
    assertEq(newDestinationNonce, currentDestinationNonce + 1);
  }
}
