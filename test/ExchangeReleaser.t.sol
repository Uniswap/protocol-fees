// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {PhoenixTestBase} from "./utils/PhoenixTestBase.sol";
import {CurrencyLibrary} from "v4-core/types/Currency.sol";
import {ExchangeReleaserMock} from "./mocks/ExchangeReleaserMock.sol";
import {INonce} from "../src/interfaces/base/INonce.sol";

contract ExchangeReleaserTest is PhoenixTestBase {
  ExchangeReleaserMock public swapReleaser;
  address public recipient = makeAddr("RECIPIENT");

  function setUp() public override {
    super.setUp();
    // owner is the msg.sender
    vm.startPrank(owner);
    swapReleaser = new ExchangeReleaserMock(
      address(resource), INITIAL_TOKEN_AMOUNT, address(assetSink), recipient
    );

    assetSink.setReleaser(address(swapReleaser));
    swapReleaser.setThresholdSetter(owner);
    vm.stopPrank();
  }

  function test_release_release_erc20() public {
    assertEq(resource.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
    assertEq(resource.balanceOf(address(swapReleaser)), 0);
    assertEq(resource.balanceOf(recipient), 0);

    vm.startPrank(alice);
    resource.approve(address(swapReleaser), INITIAL_TOKEN_AMOUNT);
    swapReleaser.release(swapReleaser.nonce(), releaseMockToken, alice);

    assertEq(mockToken.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
    assertEq(mockToken.balanceOf(address(assetSink)), 0);
    assertEq(resource.balanceOf(alice), 0);
    assertEq(resource.balanceOf(address(swapReleaser)), 0);
    assertEq(resource.balanceOf(recipient), swapReleaser.threshold());
  }

  function test_release_release_native() public {
    assertEq(resource.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
    assertEq(resource.balanceOf(address(swapReleaser)), 0);
    assertEq(resource.balanceOf(recipient), 0);

    vm.startPrank(alice);
    resource.approve(address(swapReleaser), INITIAL_TOKEN_AMOUNT);
    swapReleaser.release(swapReleaser.nonce(), releaseMockNative, alice);

    assertEq(CurrencyLibrary.ADDRESS_ZERO.balanceOf(address(assetSink)), 0);
    assertEq(resource.balanceOf(alice), 0);
    assertEq(resource.balanceOf(address(swapReleaser)), 0);
    assertEq(resource.balanceOf(recipient), swapReleaser.threshold());
  }

  function test_fuzz_revert_release_insufficient_balance(uint256 amount, uint256 seed) public {
    amount = bound(amount, 1, resource.balanceOf(alice));

    // alice spends some of her resources
    vm.prank(alice);
    bool success = resource.transfer(recipient, amount);
    assertTrue(success);
    assertLt(resource.balanceOf(alice), swapReleaser.threshold());

    uint256 nonce = swapReleaser.nonce();

    vm.startPrank(alice);
    resource.approve(address(swapReleaser), type(uint256).max);
    vm.expectRevert(); // reverts on token insufficient allowance
    swapReleaser.release(nonce, fuzzReleaseAny[seed % fuzzReleaseAny.length], alice);
  }

  function test_fuzz_revert_release_invalid_nonce(uint256 nonce, uint256 seed) public {
    vm.assume(nonce != swapReleaser.nonce()); // Ensure nonce is not the current nonce

    vm.startPrank(alice);
    resource.approve(address(swapReleaser), type(uint256).max);
    vm.expectRevert(INonce.InvalidNonce.selector);
    swapReleaser.release(nonce, fuzzReleaseAny[seed % fuzzReleaseAny.length], alice);
  }

  /// @dev test that two transactions with the same nonce, the second one should revert
  function test_revert_release_frontrun() public {
    uint256 nonce = swapReleaser.nonce();

    vm.startPrank(alice);
    resource.approve(address(swapReleaser), type(uint256).max);

    // First release call
    swapReleaser.release(nonce, releaseMockToken, alice);
    assertEq(mockToken.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
    assertEq(mockToken.balanceOf(address(assetSink)), 0);
    assertEq(resource.balanceOf(alice), 0);
    assertEq(resource.balanceOf(address(swapReleaser)), 0);
    assertEq(resource.balanceOf(recipient), INITIAL_TOKEN_AMOUNT);

    // Attempt to frontrun with the same nonce
    vm.expectRevert(INonce.InvalidNonce.selector);
    swapReleaser.release(nonce, releaseMockToken, alice);
  }
}
