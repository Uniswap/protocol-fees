// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {UNIVesting} from "../src/UNIVesting.sol";
import {IUNIVesting} from "../src/interfaces/IUNIVesting.sol";
import {
  BokkyPooBahsDateTimeLibrary
} from "BokkyPooBahsDateTimeLibrary/contracts/BokkyPooBahsDateTimeLibrary.sol";

contract UNIVestingTest is Test {
  MockERC20 public vestingToken;
  UNIVesting public vesting;

  address recipient;
  address owner;
  uint256 constant JAN_1_2026 = 1_767_225_600;
  uint256 constant APR_1_2026 = 1_775_001_600;
  uint256 constant JUL_1_2026 = 1_782_864_000;
  uint256 constant FIVE_M = 5_000_000 ether;
  uint256 constant HUNDRED_M = 100_000_000 ether;
  uint256 constant QUARTERLY_SECONDS_ESTIMATE = 91.25 days;

  function setUp() public {
    vestingToken = new MockERC20("Test UNI", "TUNI", 18);
    recipient = makeAddr("recipient");
    owner = makeAddr("owner");
    vestingToken.mint(owner, HUNDRED_M);
    vesting = new UNIVesting(address(vestingToken), recipient);
    vesting.transferOwnership(owner);
    vm.prank(owner);
    vestingToken.approve(address(vesting), FIVE_M * 8);
  }

  function test_vesting_approval() public view {
    assertEq(vestingToken.allowance(owner, address(vesting)), FIVE_M * 8);
  }

  function test_vesting_lastUnlockTimestamp() public view {
    assertEq(vesting.lastUnlockTimestamp(), JAN_1_2026 - uint48(92 days));
  }

  function test_vesting_withdraw_revertsOnlyQuarterly(uint256 timestamp) public {
    vm.assume(timestamp < JAN_1_2026);
    vm.warp(timestamp);
    vm.expectRevert(IUNIVesting.OnlyQuarterly.selector);
    vesting.withdraw();
  }

  function test_vesting_calculate_quarters_before_start_date() public {
    // before Jan 1, 2026
    vm.warp(JAN_1_2026 - 1);
    vm.assertEq(vesting.quartersPassed(), 0);
  }

  function test_vesting_calculate_quarters_none(uint256 timestamp) public {
    // before Jan 1, 2026
    vm.assume(timestamp <= JAN_1_2026 - 1);
    vm.warp(timestamp);
    vm.assertEq(vesting.quartersPassed(), 0);
  }

  function test_vesting_calculate_quartersPassed() public {
    // Mar 1, 2026
    vm.warp(1_772_341_200);
    vm.assertEq(vesting.quartersPassed(), 1);
    // Apr 1, 2026
    vm.warp(APR_1_2026);
    vm.assertEq(vesting.quartersPassed(), 2);
    // Apr 8, 2026
    vm.warp(1_775_664_000);
    vm.assertEq(vesting.quartersPassed(), 2);
    // Sep 21, 2030
    vm.warp(1_916_269_541);
    vm.assertEq(vesting.quartersPassed(), 19);
  }

  function test_fuzz_vesting_calculate_quarters(uint48 timestamp) public {
    // assume less than jan 1 2100, when the first 100 year leap skip
    vm.assume(timestamp < 4_102_462_800);
    vm.warp(timestamp);
    if (timestamp < JAN_1_2026) {
      vm.assertEq(vesting.quartersPassed(), 0);
    } else {
      vm.assertApproxEqAbs(
        vesting.quartersPassed(),
        (timestamp - JAN_1_2026) / QUARTERLY_SECONDS_ESTIMATE + 1,
        1,
        "Quarter vs estimate divergence"
      );
    }
  }

  function test_vesting_withdraw() public {
    uint256 timestamp = JAN_1_2026;
    vm.warp(timestamp);

    uint256 startingOwnerBalance = vestingToken.balanceOf(owner);
    vm.expectEmit(true, true, true, true);
    emit IUNIVesting.Withdrawn(recipient, FIVE_M, 1);
    vesting.withdraw();

    assertEq(vesting.lastUnlockTimestamp(), timestamp);
    assertEq(vestingToken.balanceOf(recipient), vesting.quarterlyVestingAmount());
    assertEq(vestingToken.balanceOf(owner), startingOwnerBalance - vesting.quarterlyVestingAmount());
  }

  function test_vesting_withdraw_two_quartersPassed() public {
    uint256 timestamp = APR_1_2026;
    vm.warp(timestamp);

    vm.expectEmit(true, true, true, true);
    emit IUNIVesting.Withdrawn(recipient, FIVE_M * 2, 2);
    vesting.withdraw();

    assertEq(vesting.lastUnlockTimestamp(), APR_1_2026);
    assertEq(vestingToken.balanceOf(recipient), vesting.quarterlyVestingAmount() * 2);
  }

  function test_vesting_withdraw_updates_lastUnlockTimestamp() public {
    uint256 timestamp = JAN_1_2026 + 500;
    vm.warp(timestamp);
    vesting.withdraw();

    assertEq(vesting.lastUnlockTimestamp(), JAN_1_2026);
    assertEq(vestingToken.balanceOf(recipient), vesting.quarterlyVestingAmount());
  }

  function test_fuzz_vesting_withdraw(uint48 timestamp) public {
    // assume less than jan 1 2100, when the first 100 year leap skip
    vm.assume(timestamp < 4_102_462_800);
    vm.warp(timestamp);

    uint256 quarters = vesting.quartersPassed();

    if (quarters == 0) {
      vm.expectRevert(IUNIVesting.OnlyQuarterly.selector);
      vesting.withdraw();
    } else {
      // The setup only approves 8 quarters worth (40M)
      uint48 expectedQuartersPaid = quarters > 8 ? 8 : uint48(quarters);
      uint256 expectedWithdrawal = uint256(expectedQuartersPaid) * vesting.quarterlyVestingAmount();

      // Calculate expected timestamp after withdrawal
      uint48 lastTimestampBefore = vesting.lastUnlockTimestamp();
      uint48 expectedTimestamp = uint48(
        BokkyPooBahsDateTimeLibrary.addMonths(lastTimestampBefore, expectedQuartersPaid * 3)
      );

      vm.expectEmit(true, true, true, true);
      emit IUNIVesting.Withdrawn(recipient, expectedWithdrawal, expectedQuartersPaid);
      vesting.withdraw();

      assertEq(vestingToken.balanceOf(recipient), expectedWithdrawal);

      // If more than 8 quarters vested, there should be remaining quarters
      if (quarters > 8) assertEq(vesting.quartersPassed(), quarters - 8);
      else assertEq(vesting.quartersPassed(), 0);
    }
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

  function test_vesting_updateRecipient_revertsNoChangeUpdate() public {
    // Try to update recipient to the same address as owner
    vm.prank(owner);
    vm.expectRevert(IUNIVesting.NoChangeUpdate.selector);
    vesting.updateRecipient(recipient);

    // Also test as recipient trying to update to same address
    vm.prank(recipient);
    vm.expectRevert(IUNIVesting.NoChangeUpdate.selector);
    vesting.updateRecipient(recipient);
  }

  function test_vesting_updateVestingAmount_revertsCannotUpdateAmount() public {
    uint256 newAmount = 10_000_000e18;

    // Warp past the start time so quartersPassed() > 0
    vm.warp(JAN_1_2026);

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

    vm.warp(JAN_1_2026 - 1);

    vm.prank(owner);
    vesting.updateVestingAmount(newAmount);

    assertEq(vesting.quarterlyVestingAmount(), newAmount);
  }

  function test_vesting_updateVestingAmount_revertsNoChangeUpdate() public {
    // Warp to before the first unlock so we can update the amount
    vm.warp(JAN_1_2026 - 1);

    // Try to update vesting amount to the same value (5_000_000 ether is the default)
    vm.prank(owner);
    vm.expectRevert(IUNIVesting.NoChangeUpdate.selector);
    vesting.updateVestingAmount(5_000_000 ether);

    // Verify the amount hasn't changed
    assertEq(vesting.quarterlyVestingAmount(), 5_000_000 ether);
  }

  function test_withdraw_partialAllowance_onlyAdvancesPaidquartersPassed() public {
    // Setup: 3 quarters pass (15M tokens vested)
    // Jul 1, 2026 is 9 months from lastUnlockTimestamp (Oct 1, 2025) = 3 quarters
    vm.warp(JUL_1_2026); // Jul 1, 2026
    assertEq(vesting.quartersPassed(), 3);

    // Owner only approves 2 quarters worth (10M)
    vm.prank(owner);
    vestingToken.approve(address(vesting), FIVE_M * 2);

    // First withdrawal: 2 quarters paid out of 3 vested
    uint48 startTimestamp = vesting.lastUnlockTimestamp();
    uint48 expectedTimestamp1 = uint48(BokkyPooBahsDateTimeLibrary.addMonths(startTimestamp, 2 * 3));
    vm.expectEmit(true, true, true, true);
    emit IUNIVesting.Withdrawn(recipient, FIVE_M * 2, 2);
    vesting.withdraw();

    // Recipient gets 10M (2 quarters worth)
    assertEq(vestingToken.balanceOf(recipient), FIVE_M * 2);

    // Timestamp only advances by 2 quarters, not 3
    // So there should still be 1 quarter remaining
    assertEq(vesting.quartersPassed(), 1);

    // Now increase allowance and withdraw the remaining quarter
    vm.prank(owner);
    vestingToken.approve(address(vesting), FIVE_M);

    // Second withdrawal: 1 remaining quarter
    uint48 expectedTimestamp2 =
      uint48(BokkyPooBahsDateTimeLibrary.addMonths(expectedTimestamp1, 1 * 3));
    vm.expectEmit(true, true, true, true);
    emit IUNIVesting.Withdrawn(recipient, FIVE_M, 1);
    vesting.withdraw();

    // Total should now be 15M (3 quarters)
    assertEq(vestingToken.balanceOf(recipient), FIVE_M * 3);
    assertEq(vesting.quartersPassed(), 0);
  }

  function test_withdraw_partialAllowance_lessThanOneQuarter_reverts() public {
    // Setup: 3 quarters pass (15M tokens vested)
    vm.warp(JUL_1_2026);
    assertEq(vesting.quartersPassed(), 3);

    // Owner approves less than 1 quarter
    vm.prank(owner);
    vestingToken.approve(address(vesting), FIVE_M - 1);

    // Should revert with insufficient allowance message
    vm.expectRevert(IUNIVesting.InsufficientAllowance.selector);
    vesting.withdraw();
  }

  function test_withdraw_partialAllowance_exactlyOneQuarter() public {
    // Setup: 3 quarters pass
    vm.warp(JUL_1_2026);
    assertEq(vesting.quartersPassed(), 3);

    // Owner approves exactly 1 quarter
    vm.prank(owner);
    vestingToken.approve(address(vesting), FIVE_M);

    uint48 startTimestamp = vesting.lastUnlockTimestamp();
    uint48 expectedTimestamp = uint48(BokkyPooBahsDateTimeLibrary.addMonths(startTimestamp, 1 * 3));
    vm.expectEmit(true, true, true, true);
    emit IUNIVesting.Withdrawn(recipient, FIVE_M, 1);
    vesting.withdraw();

    // Should withdraw 1 quarter, leaving 2 remaining
    assertEq(vestingToken.balanceOf(recipient), FIVE_M);
    assertEq(vesting.quartersPassed(), 2);
  }

  function test_withdraw_zeroAllowance_reverts() public {
    // Setup: 1 quarter passes
    vm.warp(JAN_1_2026);

    // Remove all allowance
    vm.prank(owner);
    vestingToken.approve(address(vesting), 0);

    // Should revert
    vm.expectRevert(IUNIVesting.InsufficientAllowance.selector);
    vesting.withdraw();
  }

  function test_withdraw_sequentialPartialWithdrawals() public {
    // Setup: 5 quarters pass (25M tokens vested)
    // Using Jan 1, 2028 which gives exactly 8 quarters (24 months from Jan 1, 2026)
    // We'll test with 5 quarters of partial withdrawals
    vm.warp(1_830_315_600); // Jan 1, 2028 (24 months = 8 quarters from Jan 1, 2026)
    uint256 totalQuarters = vesting.quartersPassed();
    assertGe(totalQuarters, 5); // At least 5 quarters available

    uint48 startTimestamp = vesting.lastUnlockTimestamp();

    // First withdrawal: approve and withdraw 2 quarters
    vm.prank(owner);
    vestingToken.approve(address(vesting), FIVE_M * 2);

    uint48 expectedTimestamp1 = uint48(BokkyPooBahsDateTimeLibrary.addMonths(startTimestamp, 2 * 3));
    vm.expectEmit(true, true, true, true);
    emit IUNIVesting.Withdrawn(recipient, FIVE_M * 2, 2);
    vesting.withdraw();

    assertEq(vestingToken.balanceOf(recipient), FIVE_M * 2);
    assertEq(vesting.quartersPassed(), totalQuarters - 2);

    // Second withdrawal: approve and withdraw 1 quarter
    vm.prank(owner);
    vestingToken.approve(address(vesting), FIVE_M);

    uint48 expectedTimestamp2 =
      uint48(BokkyPooBahsDateTimeLibrary.addMonths(expectedTimestamp1, 1 * 3));
    vm.expectEmit(true, true, true, true);
    emit IUNIVesting.Withdrawn(recipient, FIVE_M, 1);
    vesting.withdraw();

    assertEq(vestingToken.balanceOf(recipient), FIVE_M * 3);
    assertEq(vesting.quartersPassed(), totalQuarters - 3);

    // Third withdrawal: approve and withdraw 2 more quarters (total 5)
    vm.prank(owner);
    vestingToken.approve(address(vesting), FIVE_M * 2);

    uint48 expectedTimestamp3 =
      uint48(BokkyPooBahsDateTimeLibrary.addMonths(expectedTimestamp2, 2 * 3));
    vm.expectEmit(true, true, true, true);
    emit IUNIVesting.Withdrawn(recipient, FIVE_M * 2, 2);
    vesting.withdraw();

    assertEq(vestingToken.balanceOf(recipient), FIVE_M * 5);
    assertEq(vesting.quartersPassed(), totalQuarters - 5);
  }

  function test_ownership_transferAfterSomeQuartersVested() public {
    // Setup: 2 quarters vest, recipient withdraws 1 quarter
    vm.warp(APR_1_2026); // 2 quarters available

    // Owner approves only 1 quarter
    vm.prank(owner);
    vestingToken.approve(address(vesting), FIVE_M);

    // Recipient withdraws 1 quarter
    vesting.withdraw();
    assertEq(vestingToken.balanceOf(recipient), FIVE_M);
    assertEq(vesting.quartersPassed(), 1); // 1 quarter remaining

    // Transfer ownership to new owner
    address newOwner = makeAddr("newOwner");
    vestingToken.mint(newOwner, HUNDRED_M);

    vm.prank(owner);
    vesting.transferOwnership(newOwner);
    assertEq(vesting.owner(), newOwner);

    // After ownership transfer, new owner needs to approve
    vm.prank(newOwner);
    vestingToken.approve(address(vesting), FIVE_M);

    vesting.withdraw();
    assertEq(vestingToken.balanceOf(recipient), FIVE_M * 2);
    assertEq(vesting.quartersPassed(), 0);
  }

  function test_ownership_newOwnerChangesAllowance() public {
    // Setup: 2 quarters vest
    vm.warp(APR_1_2026);
    assertEq(vesting.quartersPassed(), 2);

    // Transfer ownership
    address newOwner = makeAddr("newOwner");
    vestingToken.mint(newOwner, HUNDRED_M);

    vm.prank(owner);
    vesting.transferOwnership(newOwner);

    // Old owner's allowance exists but new owner hasn't approved
    assertEq(vestingToken.allowance(owner, address(vesting)), FIVE_M * 8);
    assertEq(vestingToken.allowance(newOwner, address(vesting)), 0);

    // Withdrawal should fail because new owner has no allowance
    vm.expectRevert(IUNIVesting.InsufficientAllowance.selector);
    vesting.withdraw();

    // New owner approves tokens
    vm.prank(newOwner);
    vestingToken.approve(address(vesting), FIVE_M * 10);

    // Now withdrawal works with new owner's tokens
    vesting.withdraw();
    assertEq(vestingToken.balanceOf(recipient), FIVE_M * 2);
    assertEq(vestingToken.balanceOf(newOwner), HUNDRED_M - FIVE_M * 2);
    assertEq(vestingToken.balanceOf(owner), HUNDRED_M); // Old owner keeps their tokens
  }

  function test_ownership_newOwnerCanWithdraw() public {
    // Setup: vest 1 quarter
    vm.warp(JAN_1_2026);

    // Transfer ownership
    address newOwner = makeAddr("newOwner");
    vestingToken.mint(newOwner, HUNDRED_M);

    vm.prank(owner);
    vesting.transferOwnership(newOwner);

    // New owner must approve before withdrawal
    vm.prank(newOwner);
    vestingToken.approve(address(vesting), FIVE_M);

    // Anyone can call withdraw (it's public)
    vesting.withdraw();

    // Tokens go to recipient, not new owner
    assertEq(vestingToken.balanceOf(recipient), FIVE_M);
    assertEq(vestingToken.balanceOf(newOwner), HUNDRED_M - FIVE_M);
  }

  function test_ownership_transferDuringVesting() public {
    // Setup: Start with 3 quarters vested
    vm.warp(JUL_1_2026);
    assertEq(vesting.quartersPassed(), 3);

    // Withdraw 1 quarter
    vm.prank(owner);
    vestingToken.approve(address(vesting), FIVE_M);
    vesting.withdraw();
    assertEq(vestingToken.balanceOf(recipient), FIVE_M);

    // Transfer ownership mid-vesting
    address newOwner = makeAddr("newOwner");
    vestingToken.mint(newOwner, HUNDRED_M);

    vm.prank(owner);
    vesting.transferOwnership(newOwner);

    // New owner updates recipient
    address newRecipient = makeAddr("newRecipient");
    vm.prank(newOwner);
    vesting.updateRecipient(newRecipient);

    // New owner approves and withdraws remaining quarters
    vm.prank(newOwner);
    vestingToken.approve(address(vesting), FIVE_M * 2);
    vesting.withdraw();

    // New recipient gets the remaining 2 quarters
    assertEq(vestingToken.balanceOf(newRecipient), FIVE_M * 2);
    assertEq(vestingToken.balanceOf(recipient), FIVE_M); // Old recipient keeps their withdrawn
  }

  function test_recipientChange_betweenquartersPassed() public {
    // Setup: Vest 3 quarters
    vm.warp(JUL_1_2026);
    assertEq(vesting.quartersPassed(), 3);

    address recipientA = recipient;
    address recipientB = makeAddr("recipientB");

    // RecipientA withdraws quarter 1
    vm.prank(owner);
    vestingToken.approve(address(vesting), FIVE_M);
    vesting.withdraw();
    assertEq(vestingToken.balanceOf(recipientA), FIVE_M);
    assertEq(vesting.quartersPassed(), 2); // 2 quarters remaining

    // RecipientA changes to RecipientB
    vm.prank(recipientA);
    vesting.updateRecipient(recipientB);
    assertEq(vesting.recipient(), recipientB);

    // RecipientB withdraws quarter 2
    vm.prank(owner);
    vestingToken.approve(address(vesting), FIVE_M);
    vesting.withdraw();
    assertEq(vestingToken.balanceOf(recipientB), FIVE_M);
    assertEq(vesting.quartersPassed(), 1); // 1 quarter remaining

    // RecipientB changes to new address
    address recipientC = makeAddr("recipientC");
    vm.prank(recipientB);
    vesting.updateRecipient(recipientC);

    // RecipientC withdraws quarter 3
    vm.prank(owner);
    vestingToken.approve(address(vesting), FIVE_M);
    vesting.withdraw();
    assertEq(vestingToken.balanceOf(recipientC), FIVE_M);

    // Verify final balances
    assertEq(vestingToken.balanceOf(recipientA), FIVE_M);
    assertEq(vestingToken.balanceOf(recipientB), FIVE_M);
    assertEq(vestingToken.balanceOf(recipientC), FIVE_M);
    assertEq(vesting.quartersPassed(), 0);
  }

  function test_recipientChange_ownerChangesWhileVested() public {
    // Setup: Vest 2 quarters but don't withdraw
    vm.warp(APR_1_2026);
    assertEq(vesting.quartersPassed(), 2);

    address originalRecipient = recipient;
    address newRecipient = makeAddr("newRecipient");

    // Owner changes recipient while quarters are vested but not withdrawn
    vm.prank(owner);
    vesting.updateRecipient(newRecipient);

    // New recipient withdraws all vested quarters
    vesting.withdraw();

    // All tokens go to new recipient, original gets nothing
    assertEq(vestingToken.balanceOf(newRecipient), FIVE_M * 2);
    assertEq(vestingToken.balanceOf(originalRecipient), 0);
  }

  function test_recipientChange_multipleChangesBeforeWithdrawal() public {
    // Setup: Vest 1 quarter
    vm.warp(JAN_1_2026);

    address recipient1 = recipient;
    address recipient2 = makeAddr("recipient2");
    address recipient3 = makeAddr("recipient3");

    // Multiple recipient changes before withdrawal
    vm.prank(recipient1);
    vesting.updateRecipient(recipient2);

    vm.prank(recipient2);
    vesting.updateRecipient(recipient3);

    vm.prank(owner);
    vesting.updateRecipient(recipient1); // Owner changes back to original

    // Withdraw - tokens go to current recipient
    vesting.withdraw();

    assertEq(vestingToken.balanceOf(recipient1), FIVE_M);
    assertEq(vestingToken.balanceOf(recipient2), 0);
    assertEq(vestingToken.balanceOf(recipient3), 0);
  }

  function test_recipientChange_partialWithdrawalThenChange() public {
    // Setup: Vest 4 quarters
    vm.warp(1_830_315_600); // Jan 1, 2028
    uint256 quarters = vesting.quartersPassed();
    assertGe(quarters, 4);

    address recipientA = recipient;
    address recipientB = makeAddr("recipientB");

    // RecipientA withdraws 2 quarters (partial)
    vm.prank(owner);
    vestingToken.approve(address(vesting), FIVE_M * 2);
    vesting.withdraw();
    assertEq(vestingToken.balanceOf(recipientA), FIVE_M * 2);

    // RecipientA transfers rights to RecipientB
    vm.prank(recipientA);
    vesting.updateRecipient(recipientB);

    // Owner increases allowance
    vm.prank(owner);
    vestingToken.approve(address(vesting), FIVE_M * 2);

    // RecipientB withdraws remaining quarters
    vesting.withdraw();
    assertEq(vestingToken.balanceOf(recipientB), FIVE_M * 2);

    // Verify both recipients got their share
    assertEq(vestingToken.balanceOf(recipientA), FIVE_M * 2);
    assertEq(vestingToken.balanceOf(recipientB), FIVE_M * 2);
  }
}
