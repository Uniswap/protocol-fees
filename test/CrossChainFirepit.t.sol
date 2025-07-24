// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {PhoenixTestBase} from "./utils/PhoenixTestBase.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Firepit} from "../src/Firepit.sol";
import {AssetSink} from "../src/AssetSink.sol";
import {Nonce} from "../src/base/Nonce.sol";

contract CrossChainFirepitTest is PhoenixTestBase {
  uint32 public constant L2_GAS_LIMIT = 1_000_000;

  function setUp() public override {
    super.setUp();

    vm.prank(owner);
    assetSink.setReleaser(address(firepitDestination));
  }

  function test_torch_release_erc20() public {
    assertEq(resource.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
    assertEq(resource.balanceOf(address(opStackFirepitSource)), 0);
    assertEq(resource.balanceOf(address(0)), 0);

    vm.startPrank(alice);
    resource.approve(address(opStackFirepitSource), INITIAL_TOKEN_AMOUNT);
    opStackFirepitSource.torch(
      opStackFirepitSource.nonce(),
      firepitDestination.nonce(),
      releaseMockToken,
      alice,
      L2_GAS_LIMIT
    );
    vm.stopPrank();

    assertEq(mockToken.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
    assertEq(mockToken.balanceOf(address(assetSink)), 0);
    assertEq(resource.balanceOf(alice), 0);
    assertEq(resource.balanceOf(address(opStackFirepitSource)), 0);
    assertEq(resource.balanceOf(address(0)), opStackFirepitSource.THRESHOLD());
  }

  function test_torch_release_native() public {}

  function test_fuzz_revert_torch_insufficient_balance(uint256 amount, uint256 seed) public {}

  function test_fuzz_revert_torch_invalid_nonce(uint256 nonce, uint256 seed) public {}

  /// @dev test that two transactions with the same nonce, the second one should revert
  function test_revert_torch_frontrun() public {}
}
