// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {PhoenixTestBase} from "./utils/PhoenixTestBase.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Firepit} from "../src/Firepit.sol";
import {AssetSink} from "../src/AssetSink.sol";
import {Nonce} from "../src/base/Nonce.sol";

contract FirepitTest is PhoenixTestBase {
  function setUp() public override {
    super.setUp();

    vm.prank(owner);
    assetSink.setReleaser(address(firepit));
  }

  function test_torch_release_erc20() public {
    assertEq(resource.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
    assertEq(resource.balanceOf(address(firepit)), 0);
    assertEq(resource.balanceOf(address(0)), 0);

    vm.startPrank(alice);
    resource.approve(address(firepit), INITIAL_TOKEN_AMOUNT);
    firepit.torch(firepit.nonce(), releaseMockToken, alice);

    assertEq(mockToken.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
    assertEq(mockToken.balanceOf(address(assetSink)), 0);
    assertEq(resource.balanceOf(alice), 0);
    assertEq(resource.balanceOf(address(firepit)), 0);
    assertEq(resource.balanceOf(address(0)), firepit.THRESHOLD());
  }

  function test_torch_release_native() public {
    assertEq(resource.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
    assertEq(resource.balanceOf(address(firepit)), 0);
    assertEq(resource.balanceOf(address(0)), 0);

    vm.startPrank(alice);
    resource.approve(address(firepit), INITIAL_TOKEN_AMOUNT);
    firepit.torch(firepit.nonce(), releaseMockNative, alice);

    assertEq(CurrencyLibrary.ADDRESS_ZERO.balanceOf(address(assetSink)), 0);
    assertEq(resource.balanceOf(alice), 0);
    assertEq(resource.balanceOf(address(firepit)), 0);
    assertEq(resource.balanceOf(address(0)), firepit.THRESHOLD());
  }

  function test_fuzz_revert_torch_insufficient_balance(uint256 amount, uint256 seed) public {
    amount = bound(amount, 1, resource.balanceOf(alice));

    // alice spends some of her resources
    vm.prank(alice);
    resource.transfer(address(0), amount);

    assertLt(resource.balanceOf(alice), firepit.THRESHOLD());

    uint256 nonce = firepit.nonce();

    vm.startPrank(alice);
    resource.approve(address(firepit), type(uint256).max);
    vm.expectRevert(); // reverts on token insufficient allowance
    firepit.torch(nonce, fuzzReleaseAny[seed % fuzzReleaseAny.length], alice);
  }

  function test_fuzz_revert_torch_invalid_nonce(uint256 nonce, uint256 seed) public {
    vm.assume(nonce != firepit.nonce()); // Ensure nonce is not the current nonce

    vm.startPrank(alice);
    resource.approve(address(firepit), type(uint256).max);
    vm.expectRevert(Nonce.InvalidNonce.selector);
    firepit.torch(nonce, fuzzReleaseAny[seed % fuzzReleaseAny.length], alice);
  }

  /// @dev test that two transactions with the same nonce, the second one should revert
  function test_revert_torch_frontrun() public {
    uint256 nonce = firepit.nonce();

    vm.startPrank(alice);
    resource.approve(address(firepit), type(uint256).max);

    // First torch call
    firepit.torch(nonce, releaseMockToken, alice);
    assertEq(mockToken.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
    assertEq(mockToken.balanceOf(address(assetSink)), 0);
    assertEq(resource.balanceOf(alice), 0);
    assertEq(resource.balanceOf(address(firepit)), 0);
    assertEq(resource.balanceOf(address(0)), INITIAL_TOKEN_AMOUNT);

    // Attempt to frontrun with the same nonce
    vm.expectRevert(Nonce.InvalidNonce.selector);
    firepit.torch(nonce, releaseMockToken, alice);
  }
}
