// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {MainnetDeployer} from "../script/deployers/MainnetDeployer.sol";
import {IUNIVesting} from "../src/interfaces/IUNIVesting.sol";
import {UnificationProposal} from "../script/04_UnificationProposal.s.sol";
import {IOwned} from "../src/interfaces/base/IOwned.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract UNIVestingForkTest is Test {
  MainnetDeployer public deployer;
  IUNIVesting public uniVesting;
  IUniswapV3Factory public factory;

  address public owner;
  address public recipient;
  address public UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

  // January 1, 2026 00:00:00 UTC
  uint256 constant FIRST_UNLOCK_TIMESTAMP = 1_767_225_600;
  uint256 constant MONTHS_PER_QUARTER = 3;
  uint256 constant QUARTERLY_AMOUNT = 5_000_000 ether;

  function setUp() public {
    vm.createSelectFork("mainnet");
    factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    owner = factory.owner();

    // Deploy and run the proposal
    deployer = new MainnetDeployer();
    UnificationProposal proposal = new UnificationProposal();
    proposal.runPranked(deployer);

    uniVesting = deployer.UNI_VESTING();
    recipient = uniVesting.recipient();
  }

  function test_initialSetup() public view {
    // Verify deployment
    assertEq(address(uniVesting.UNI()), UNI, "UNI token address mismatch");
    assertEq(uniVesting.recipient(), deployer.LABS_UNI_RECIPIENT(), "Recipient mismatch");
    assertEq(uniVesting.quarterlyVestingAmount(), QUARTERLY_AMOUNT, "Quarterly amount mismatch");
    assertEq(IOwned(address(uniVesting)).owner(), owner, "Owner mismatch");

    // Verify owner has approved UNIVesting contract
    uint256 allowance = IERC20(UNI).allowance(owner, address(uniVesting));
    assertEq(allowance, 40_000_000 ether, "Allowance not set correctly");

    // Verify no quarters are available yet
    assertEq(uniVesting.quartersPassed(), 0, "Should have no quarters passed initially");
  }

  function test_withdrawBeforeFirstUnlock() public {
    // Warp to a time before the first unlock (e.g., December 31, 2025)
    vm.warp(FIRST_UNLOCK_TIMESTAMP - 1 days);

    // Should revert when trying to withdraw before first unlock
    vm.expectRevert(IUNIVesting.OnlyQuarterly.selector);
    uniVesting.withdraw();
  }

  function test_withdrawSingleQuarter() public {
    // Warp to just after the first unlock
    vm.warp(FIRST_UNLOCK_TIMESTAMP + 1 days);

    // Should have exactly 1 quarter available
    assertEq(uniVesting.quartersPassed(), 1, "Should have 1 quarter passed");

    uint256 recipientBalanceBefore = IERC20(UNI).balanceOf(recipient);
    uint256 ownerBalanceBefore = IERC20(UNI).balanceOf(owner);

    // Anyone can call withdraw
    vm.prank(address(0xdead));
    uniVesting.withdraw();

    // Verify transfer
    uint256 recipientBalanceAfter = IERC20(UNI).balanceOf(recipient);
    uint256 ownerBalanceAfter = IERC20(UNI).balanceOf(owner);

    assertEq(
      recipientBalanceAfter - recipientBalanceBefore,
      QUARTERLY_AMOUNT,
      "Recipient should receive quarterly amount"
    );
    assertEq(
      ownerBalanceBefore - ownerBalanceAfter,
      QUARTERLY_AMOUNT,
      "Owner balance should decrease by quarterly amount"
    );

    // Should have no quarters available after withdrawal
    assertEq(uniVesting.quartersPassed(), 0, "Should have no quarters after withdrawal");
  }

  function test_withdrawMultipleQuarters() public {
    // Warp to 3 quarters after first unlock
    // Using 270 days for approximately 9 months (3 quarters)
    vm.warp(FIRST_UNLOCK_TIMESTAMP + 270 days);

    // Should have 3 quarters available
    uint48 quarters = uniVesting.quartersPassed();
    assertGe(quarters, 3, "Should have at least 3 quarters passed");

    uint256 recipientBalanceBefore = IERC20(UNI).balanceOf(recipient);

    uniVesting.withdraw();

    uint256 recipientBalanceAfter = IERC20(UNI).balanceOf(recipient);
    assertEq(
      recipientBalanceAfter - recipientBalanceBefore,
      QUARTERLY_AMOUNT * quarters,
      "Should receive correct number of quarters"
    );

    // Should have no quarters available after withdrawal
    assertEq(uniVesting.quartersPassed(), 0, "Should have no quarters after withdrawal");
  }

  function test_partialWithdrawal() public {
    // Warp to 3 quarters after first unlock
    vm.warp(FIRST_UNLOCK_TIMESTAMP + 270 days);
    uint48 quarters = uniVesting.quartersPassed();
    assertGe(quarters, 3, "Should have at least 3 quarters passed");

    // Reduce allowance to only cover 2 quarters
    vm.prank(owner);
    IERC20(UNI).approve(address(uniVesting), QUARTERLY_AMOUNT * 2);

    uint256 recipientBalanceBefore = IERC20(UNI).balanceOf(recipient);

    uniVesting.withdraw();

    uint256 recipientBalanceAfter = IERC20(UNI).balanceOf(recipient);
    assertEq(
      recipientBalanceAfter - recipientBalanceBefore,
      QUARTERLY_AMOUNT * 2,
      "Should only receive 2 quarters due to limited allowance"
    );

    // Should still have remaining quarters available
    uint48 remainingQuarters = uniVesting.quartersPassed();
    assertGe(remainingQuarters, 1, "Should have at least 1 quarter remaining");

    // Restore allowance and withdraw remaining quarters
    vm.prank(owner);
    IERC20(UNI).approve(address(uniVesting), QUARTERLY_AMOUNT * remainingQuarters);

    recipientBalanceBefore = recipientBalanceAfter;
    uniVesting.withdraw();
    recipientBalanceAfter = IERC20(UNI).balanceOf(recipient);

    assertEq(
      recipientBalanceAfter - recipientBalanceBefore,
      QUARTERLY_AMOUNT * remainingQuarters,
      "Should receive the remaining quarters"
    );
    assertEq(uniVesting.quartersPassed(), 0, "Should have no quarters remaining");
  }

  function test_insufficientAllowance() public {
    // Warp to after first unlock
    vm.warp(FIRST_UNLOCK_TIMESTAMP + 1 days);

    // Remove allowance completely
    vm.prank(owner);
    IERC20(UNI).approve(address(uniVesting), 0);

    // Should revert due to insufficient allowance
    vm.expectRevert(IUNIVesting.InsufficientAllowance.selector);
    uniVesting.withdraw();
  }

  function test_updateRecipientByOwner() public {
    address newRecipient = address(0x123);

    // Owner can update recipient
    vm.prank(owner);
    uniVesting.updateRecipient(newRecipient);

    assertEq(uniVesting.recipient(), newRecipient, "Recipient should be updated");

    // Verify vesting works with new recipient
    vm.warp(FIRST_UNLOCK_TIMESTAMP + 1 days);

    uint256 newRecipientBalanceBefore = IERC20(UNI).balanceOf(newRecipient);
    uniVesting.withdraw();
    uint256 newRecipientBalanceAfter = IERC20(UNI).balanceOf(newRecipient);

    assertEq(
      newRecipientBalanceAfter - newRecipientBalanceBefore,
      QUARTERLY_AMOUNT,
      "New recipient should receive tokens"
    );
  }

  function test_updateRecipientByRecipient() public {
    address newRecipient = address(0x456);

    // Current recipient can update to new recipient
    vm.prank(recipient);
    uniVesting.updateRecipient(newRecipient);

    assertEq(uniVesting.recipient(), newRecipient, "Recipient should be updated");
  }

  function test_updateRecipientUnauthorized() public {
    address newRecipient = address(0x789);

    // Random address cannot update recipient
    vm.prank(address(0xdead));
    vm.expectRevert(IUNIVesting.NotAuthorized.selector);
    uniVesting.updateRecipient(newRecipient);
  }

  function test_updateVestingAmountNoQuarters() public {
    uint256 newAmount = 10_000_000 ether;

    // Owner can update vesting amount when no quarters are available
    vm.prank(owner);
    uniVesting.updateVestingAmount(newAmount);

    assertEq(uniVesting.quarterlyVestingAmount(), newAmount, "Vesting amount should be updated");

    // Verify the new amount is used for withdrawals
    vm.warp(FIRST_UNLOCK_TIMESTAMP + 1 days);

    // Update allowance for new amount
    vm.prank(owner);
    IERC20(UNI).approve(address(uniVesting), newAmount);

    uint256 recipientBalanceBefore = IERC20(UNI).balanceOf(recipient);
    uniVesting.withdraw();
    uint256 recipientBalanceAfter = IERC20(UNI).balanceOf(recipient);

    assertEq(
      recipientBalanceAfter - recipientBalanceBefore,
      newAmount,
      "Should receive new quarterly amount"
    );
  }

  function test_updateVestingAmountWithQuartersAvailable() public {
    // Warp to after first unlock
    vm.warp(FIRST_UNLOCK_TIMESTAMP + 1 days);
    assertEq(uniVesting.quartersPassed(), 1, "Should have 1 quarter available");

    uint256 newAmount = 10_000_000 ether;

    // Should revert when trying to update with quarters available
    vm.prank(owner);
    vm.expectRevert(IUNIVesting.CannotUpdateAmount.selector);
    uniVesting.updateVestingAmount(newAmount);
  }

  function test_updateVestingAmountNoChange() public {
    // Should revert when trying to update to the same amount
    vm.prank(owner);
    vm.expectRevert(IUNIVesting.NoChangeUpdate.selector);
    uniVesting.updateVestingAmount(QUARTERLY_AMOUNT);
  }

  function test_longTermVesting() public {
    uint256 twoYears = 729 days;
    vm.warp(FIRST_UNLOCK_TIMESTAMP + twoYears);

    uint48 quarters = uniVesting.quartersPassed();
    assertEq(quarters, 8, "Should have at least 8 quarters after 2 years");

    uint256 recipientBalanceBefore = IERC20(UNI).balanceOf(recipient);
    uniVesting.withdraw();
    uint256 recipientBalanceAfter = IERC20(UNI).balanceOf(recipient);

    assertEq(
      recipientBalanceAfter - recipientBalanceBefore,
      QUARTERLY_AMOUNT * quarters,
      "Should receive correct amount"
    );
  }

  function test_allVestingComplete() public {
    // 40M UNI approved, 5M per quarter = 8 quarters total
    // Warp to after all vesting is complete
    vm.warp(FIRST_UNLOCK_TIMESTAMP + 730 days); // 2 years

    uint256 totalVested = 0;

    // Withdraw all available quarters
    uniVesting.withdraw();
    totalVested = IERC20(UNI).balanceOf(recipient);

    // Due to calendar-based quarters, the actual amount might be slightly more
    assertGe(totalVested, QUARTERLY_AMOUNT * 8, "Should vest at least 40M total");
    assertLe(totalVested, QUARTERLY_AMOUNT * 9, "Should not vest more than 45M");

    // Try to withdraw again - should fail due to insufficient allowance or no quarters
    // After withdrawing, either:
    // 1. No more quarters are available (OnlyQuarterly error)
    // 2. More quarters available but no allowance (InsufficientAllowance error)
    vm.warp(block.timestamp + 365 days);

    // Check if more quarters are available
    uint48 remainingQuarters = uniVesting.quartersPassed();
    if (remainingQuarters > 0) {
      // If quarters are available, should fail due to insufficient allowance
      vm.expectRevert(IUNIVesting.InsufficientAllowance.selector);
    } else {
      // If no quarters available, should fail with OnlyQuarterly
      vm.expectRevert(IUNIVesting.OnlyQuarterly.selector);
    }
    uniVesting.withdraw();
  }

  function test_ownershipTransfer() public {
    address newOwner = address(0xbeef);

    // Transfer ownership of UNIVesting contract
    vm.prank(owner);
    IOwned(address(uniVesting)).transferOwnership(newOwner);

    assertEq(IOwned(address(uniVesting)).owner(), newOwner, "Ownership should be transferred");

    // New owner needs to approve tokens for vesting to continue
    deal(UNI, newOwner, 50_000_000 ether);
    vm.prank(newOwner);
    IERC20(UNI).approve(address(uniVesting), 50_000_000 ether);

    // Verify vesting still works with new owner
    vm.warp(FIRST_UNLOCK_TIMESTAMP + 1 days);

    uint256 recipientBalanceBefore = IERC20(UNI).balanceOf(recipient);
    uniVesting.withdraw();
    uint256 recipientBalanceAfter = IERC20(UNI).balanceOf(recipient);

    assertEq(
      recipientBalanceAfter - recipientBalanceBefore,
      QUARTERLY_AMOUNT,
      "Vesting should work with new owner"
    );
  }
}

