// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {UNIVesting} from "../src/UNIVesting.sol";
import {IUNIVesting} from "../src/interfaces/IUNIVesting.sol";

contract UNIVestingTest is Test {
  MockERC20 public vestingToken;
  UNIVesting public vesting;

  address recipient;
  address owner;
  uint256 jan_1_2026 = 1_767_225_600;
  uint256 FIVE_M = 5_000_000e18;
  uint256 HUNDRED_M = 100_000_000e18;

  function setUp() public {
    vestingToken = new MockERC20("Test UNI", "TUNI", 18);
    recipient = makeAddr("recipient");
    owner = makeAddr("owner");
    vestingToken.mint(owner, HUNDRED_M);
    vesting = new UNIVesting(address(vestingToken), recipient);
    vesting.transferOwnership(owner);
    vm.prank(owner);
    vestingToken.approve(address(vesting), FIVE_M * 10);
  }

  function test_vesting_approval() public view {
    assertEq(vestingToken.allowance(owner, address(vesting)), FIVE_M * 10);
  }

  function test_vesting_start_time() public view {
    assertEq(vesting.START_TIME(), jan_1_2026);
  }

  function test_vesting_lastQuarterlyTimestamp() public view {
    assertEq(vesting.lastQuarterlyTimestamp(), jan_1_2026);
  }

  function test_vesting_withdraw_revertsOnlyQuarterly() public {
    vm.expectRevert(IUNIVesting.OnlyQuarterly.selector);
    vesting.withdraw();
  }

  function test_vesting_withdraw_after_two_quarters() public {
    uint256 timestamp = vesting.START_TIME() + 2 * vesting.QUARTERLY_SECONDS();

    // Move it slightly past the 2 quarter window to check the lastQuarterlyTimestamp value.
    vm.warp(timestamp + 100);
    vesting.withdraw();

    assertEq(vesting.lastQuarterlyTimestamp(), timestamp);
    assertEq(vestingToken.balanceOf(recipient), vesting.QUARTERLY_VESTING_AMOUNT() * 2);
  }

  function test_vesting_withdraw_at_exact_boundary() public {
    uint256 exactBoundary = vesting.START_TIME() + vesting.QUARTERLY_SECONDS();
    uint256 recipientBalanceBefore = vestingToken.balanceOf(recipient);

    vm.warp(exactBoundary);
    vesting.withdraw();

    uint256 recipientBalanceAfter = vestingToken.balanceOf(recipient);

    assertEq(recipientBalanceAfter - recipientBalanceBefore, vesting.QUARTERLY_VESTING_AMOUNT());
  }

  function test_vesting_updateRecipient_revertsNotAuthorized() public {
    address unauthorized = makeAddr("unauthorized");
    address newRecipient = makeAddr("newRecipient");

    vm.prank(unauthorized);
    vm.expectRevert(IUNIVesting.NotAuthorized.selector);
    vesting.updateRecipient(newRecipient);
  }

  function test_vesting_updateRecipient_succeedsAsOwner() public {
    address newRecipient = makeAddr("newRecipient");

    vm.prank(owner);
    vesting.updateRecipient(newRecipient);

    assertEq(vesting.recipient(), newRecipient);
  }

  function test_vesting_updateRecipient_succeedsAsRecipient() public {
    address newRecipient = makeAddr("newRecipient");

    vm.prank(recipient);
    vesting.updateRecipient(newRecipient);

    assertEq(vesting.recipient(), newRecipient);
  }

  function test_vesting_updateVestingAmount_revertsCannotUpdateAmount() public {
    uint256 newAmount = 10_000_000e18;

    // Warp past the start time so quarters() > 0
    vm.warp(vesting.START_TIME() + vesting.QUARTERLY_SECONDS());

    vm.prank(owner);
    vm.expectRevert(IUNIVesting.CannotUpdateAmount.selector);
    vesting.updateVestingAmount(newAmount);
  }

  function test_vesting_updateVestingAmount_revertsUnauthorized() public {
    address unauthorized = makeAddr("unauthorized");
    uint256 newAmount = 10_000_000e18;

    vm.prank(unauthorized);
    vm.expectRevert("UNAUTHORIZED");
    vesting.updateVestingAmount(newAmount);
  }

  function test_vesting_updateVestingAmount_succeeds() public {
    uint256 newAmount = 10_000_000e18;

    // Warp to after start time but before first quarter completes, so quarters() == 0
    vm.warp(vesting.START_TIME() + vesting.QUARTERLY_SECONDS() - 1);

    vm.prank(owner);
    vesting.updateVestingAmount(newAmount);

    assertEq(vesting.QUARTERLY_VESTING_AMOUNT(), newAmount);
  }
}
