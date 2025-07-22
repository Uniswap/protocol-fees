// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {PhoenixTestBase} from "./utils/PhoenixTestBase.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Currency} from "v4-core/types/Currency.sol";

import {Firepit} from "../src/Firepit.sol";
import {AssetSink} from "../src/AssetSink.sol";

contract FirepitTest is PhoenixTestBase {
  function setUp() public override {
    super.setUp();

    vm.prank(owner);
    assetSink.setReleaser(address(firepit));
  }

  function test_torch_success() public {
    // Assets to collect.
    Currency[] memory assets = new Currency[](1);
    assets[0] = Currency.wrap(address(mockToken));

    assertEq(resource.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
    assertEq(resource.balanceOf(address(firepit)), 0);
    assertEq(resource.balanceOf(address(0)), 0);

    vm.startPrank(alice);
    resource.approve(address(firepit), INITIAL_TOKEN_AMOUNT);
    firepit.torch(assets, alice);

    assertEq(mockToken.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
    assertEq(mockToken.balanceOf(address(assetSink)), 0);
    assertEq(resource.balanceOf(alice), 0);
    assertEq(resource.balanceOf(address(firepit)), 0);
    assertEq(resource.balanceOf(address(0)), INITIAL_TOKEN_AMOUNT);
  }

  function test_fuzz_revert_torch_insufficient_balance(uint256 amount) public {
    // Assets to collect.
    Currency[] memory assets = new Currency[](1);
    assets[0] = Currency.wrap(address(mockToken));

    amount = bound(amount, 1, resource.balanceOf(alice));
    // alice spends some of her resources
    vm.prank(alice);
    resource.transfer(address(0), amount);

    assertLt(resource.balanceOf(alice), firepit.THRESHOLD());

    vm.startPrank(alice);
    resource.approve(address(firepit), type(uint256).max);
    vm.expectRevert(address(resource)); // reverts on token insufficient allowance
    firepit.torch(assets, alice);
  }
}
