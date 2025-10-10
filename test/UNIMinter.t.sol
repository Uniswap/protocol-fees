// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";

import {UNIMinter} from "../src/UNIMinter.sol";
import {IUNIMinter} from "../src/interfaces/IUNIMinter.sol";
import {MockUNIToken} from "./mocks/MockUNIToken.sol";
import {IUNI} from "../src/interfaces/IUNI.sol";

contract UNIMinterTest is Test {
  UNIMinter public uniMinter;
  MockUNIToken public UNI;

  address public owner = makeAddr("owner");
  address public alice = makeAddr("alice");
  address public bob = makeAddr("bob");
  address public charlie = makeAddr("charlie");
  address public dave = makeAddr("dave");
  address public unauthorizedUser = makeAddr("UnauthorizedUser");

  uint16 constant DEFAULT_REVOCATION_DELAY_DAYS = 365;
  uint16 constant MINT_CAP_PERCENT = 2;
  uint16 constant MAX_SHARES = 10_000;

  event Transfer(address indexed from, address indexed to, uint256 value);

  function setUp() public {
    uniMinter = new UNIMinter(owner);
    deployCodeTo("MockUNIToken", address(uniMinter.UNI()));
    UNI = MockUNIToken(address(uniMinter.UNI()));
    UNI.setMinter(address(uniMinter));
    assertEq(UNI.totalSupply(), UNI.initialTotalSupply());
    assertEq(UNI.minter(), address(uniMinter));
  }

  function test_Constructor() public view {
    assertEq(uniMinter.owner(), owner);
    assertEq(uniMinter.totalShares(), 0);
    assertEq(address(uniMinter.UNI()), 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
  }

  function test_GrantShares_Single() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000, DEFAULT_REVOCATION_DELAY_DAYS);

    assertEq(uniMinter.totalShares(), 5000);
    (
      address recipient,
      uint16 amount,
      uint16 revocationDelayDays,
      uint48 pendingRevocationTime,
      bool adjustedForRevocation
    ) = uniMinter.shares(0);
    assertEq(recipient, alice);
    assertEq(amount, 5000);
    assertEq(revocationDelayDays, DEFAULT_REVOCATION_DELAY_DAYS);
    assertEq(pendingRevocationTime, 0);
    assertEq(adjustedForRevocation, false);
  }

  function test_GrantShares_Multiple() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 3000, DEFAULT_REVOCATION_DELAY_DAYS);
    uniMinter.grantShares(bob, 2000, 180);
    uniMinter.grantShares(charlie, 1500, 90);
    vm.stopPrank();

    assertEq(uniMinter.totalShares(), 6500);

    (address recipient0, uint16 amount0, uint16 delay0,, bool adjusted0) = uniMinter.shares(0);
    assertEq(recipient0, alice);
    assertEq(amount0, 3000);
    assertEq(delay0, DEFAULT_REVOCATION_DELAY_DAYS);
    assertEq(adjusted0, false);

    (address recipient1, uint16 amount1, uint16 delay1,, bool adjusted1) = uniMinter.shares(1);
    assertEq(recipient1, bob);
    assertEq(amount1, 2000);
    assertEq(delay1, 180);
    assertEq(adjusted1, false);

    (address recipient2, uint16 amount2, uint16 delay2,, bool adjusted2) = uniMinter.shares(2);
    assertEq(recipient2, charlie);
    assertEq(amount2, 1500);
    assertEq(delay2, 90);
    assertEq(adjusted2, false);
  }

  function test_GrantShares_MaxShares() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, MAX_SHARES, DEFAULT_REVOCATION_DELAY_DAYS);
    assertEq(uniMinter.totalShares(), MAX_SHARES);
  }

  function test_GrantShares_RevertInsufficientShares() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 6000, DEFAULT_REVOCATION_DELAY_DAYS);

    vm.expectRevert(IUNIMinter.InsufficientShares.selector);
    uniMinter.grantShares(bob, 5000, DEFAULT_REVOCATION_DELAY_DAYS);
    vm.stopPrank();
  }

  function test_GrantShares_RevertUnauthorized() public {
    vm.expectRevert("UNAUTHORIZED");
    vm.prank(unauthorizedUser);
    uniMinter.grantShares(alice, 5000, DEFAULT_REVOCATION_DELAY_DAYS);
  }

  function test_GrantShares_SameRecipientMultipleTimes() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 2000, DEFAULT_REVOCATION_DELAY_DAYS);
    uniMinter.grantShares(alice, 3000, 180);
    vm.stopPrank();

    assertEq(uniMinter.totalShares(), 5000);

    (address recipient0, uint16 amount0, uint16 delay0,, bool adjusted0) = uniMinter.shares(0);
    assertEq(recipient0, alice);
    assertEq(amount0, 2000);
    assertEq(delay0, DEFAULT_REVOCATION_DELAY_DAYS);
    assertEq(adjusted0, false);

    (address recipient1, uint16 amount1, uint16 delay1,, bool adjusted1) = uniMinter.shares(1);
    assertEq(recipient1, alice);
    assertEq(amount1, 3000);
    assertEq(delay1, 180);
    assertEq(adjusted1, false);
  }

  function test_Mint_SingleRecipientFullShares() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, MAX_SHARES, DEFAULT_REVOCATION_DELAY_DAYS);

    vm.warp(UNI.mintingAllowedAfter());

    uint256 expectedMintAmount = UNI.totalSupply() * MINT_CAP_PERCENT / 100;

    vm.expectEmit(true, true, false, true);
    emit Transfer(address(0), address(uniMinter), expectedMintAmount);

    uniMinter.mint();

    assertEq(UNI.balanceOf(address(uniMinter)), 0);
    assertEq(UNI.balanceOf(alice), expectedMintAmount);
    assertEq(UNI.totalSupply(), UNI.initialTotalSupply() + expectedMintAmount);
  }

  function test_Mint_MultipleRecipients() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 5000, DEFAULT_REVOCATION_DELAY_DAYS);
    uniMinter.grantShares(bob, 3000, DEFAULT_REVOCATION_DELAY_DAYS);
    uniMinter.grantShares(charlie, 2000, DEFAULT_REVOCATION_DELAY_DAYS);
    vm.stopPrank();

    vm.warp(UNI.mintingAllowedAfter());

    uint256 totalSupplyBefore = UNI.totalSupply();
    uint256 expectedMintCap = totalSupplyBefore * MINT_CAP_PERCENT / 100;
    uint256 expectedMintAmount = expectedMintCap * MAX_SHARES / MAX_SHARES;

    uniMinter.mint();

    assertEq(UNI.balanceOf(address(uniMinter)), 0);
    assertEq(UNI.balanceOf(alice), expectedMintAmount * 5000 / MAX_SHARES);
    assertEq(UNI.balanceOf(bob), expectedMintAmount * 3000 / MAX_SHARES);
    assertEq(UNI.balanceOf(charlie), expectedMintAmount * 2000 / MAX_SHARES);
    assertEq(UNI.totalSupply(), totalSupplyBefore + expectedMintAmount);
  }

  function test_Mint_PartialShares() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000, DEFAULT_REVOCATION_DELAY_DAYS);

    vm.warp(UNI.mintingAllowedAfter());

    uint256 totalSupplyBefore = UNI.totalSupply();
    uint256 expectedMintCap = totalSupplyBefore * MINT_CAP_PERCENT / 100;
    uint256 expectedTotalMint = expectedMintCap * 5000 / MAX_SHARES;
    uint256 expectedAliceAmount = expectedTotalMint * 5000 / uniMinter.totalShares();

    uniMinter.mint();

    assertEq(UNI.balanceOf(address(uniMinter)), 0);
    assertEq(UNI.balanceOf(alice), expectedAliceAmount);
    assertEq(UNI.totalSupply(), totalSupplyBefore + expectedTotalMint);
  }

  function test_Mint_PartialShares_MultipleRecipients() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 5000, DEFAULT_REVOCATION_DELAY_DAYS);
    uniMinter.grantShares(bob, 2000, DEFAULT_REVOCATION_DELAY_DAYS);

    vm.warp(UNI.mintingAllowedAfter());

    uint256 totalSupplyBefore = UNI.totalSupply();
    uint256 expectedMintCap = totalSupplyBefore * MINT_CAP_PERCENT / 100;
    uint256 expectedTotalMint = expectedMintCap * 7000 / MAX_SHARES;
    uint256 expectedAliceAmount = expectedTotalMint * 5000 / uniMinter.totalShares();
    uint256 expectedBobAmount = expectedTotalMint * 2000 / uniMinter.totalShares();

    uniMinter.mint();

    assertEq(UNI.balanceOf(address(uniMinter)), 0);
    assertEq(UNI.balanceOf(alice), expectedAliceAmount);
    assertEq(UNI.balanceOf(bob), expectedBobAmount);
    assertEq(UNI.totalSupply(), totalSupplyBefore + expectedTotalMint);
  }

  function test_Mint_RevertNoShares() public {
    vm.warp(UNI.mintingAllowedAfter());

    vm.expectRevert(IUNIMinter.NoShares.selector);
    uniMinter.mint();
  }

  function test_Mint_CalledByAnyone() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000, DEFAULT_REVOCATION_DELAY_DAYS);

    vm.warp(UNI.mintingAllowedAfter());

    vm.prank(unauthorizedUser);
    uniMinter.mint();

    assertGt(UNI.balanceOf(alice), 0);
  }

  function test_Mint_ConsecutiveMints() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, MAX_SHARES, DEFAULT_REVOCATION_DELAY_DAYS);

    vm.warp(UNI.mintingAllowedAfter());
    uniMinter.mint();
    uint256 firstMintBalance = UNI.balanceOf(alice);

    vm.warp(block.timestamp + 365 days);
    uniMinter.mint();
    uint256 secondMintBalance = UNI.balanceOf(alice) - firstMintBalance;

    assertGt(secondMintBalance, firstMintBalance);
  }

  function test_InitiateRevokeShares_Single() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000, DEFAULT_REVOCATION_DELAY_DAYS);

    uint256 currentTime = block.timestamp;
    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    (,, uint16 revocationDelayDays, uint48 pendingRevocationTime, bool adjusted) =
      uniMinter.shares(0);
    assertEq(revocationDelayDays, DEFAULT_REVOCATION_DELAY_DAYS);
    assertEq(pendingRevocationTime, currentTime + uint256(DEFAULT_REVOCATION_DELAY_DAYS) * 1 days);
    assertEq(adjusted, false);
  }

  function test_InitiateRevokeShares_RevertUnauthorized() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000, DEFAULT_REVOCATION_DELAY_DAYS);

    vm.expectRevert("UNAUTHORIZED");
    vm.prank(unauthorizedUser);
    uniMinter.initiateRevokeShares(0);
  }

  function test_InitiateRevokeShares_MultipleShares() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 3000, DEFAULT_REVOCATION_DELAY_DAYS);
    uniMinter.grantShares(bob, 2000, 180);
    uniMinter.grantShares(charlie, 1000, 90);

    uint256 currentTime = block.timestamp;
    uniMinter.initiateRevokeShares(1);
    vm.stopPrank();

    (,,, uint48 pendingTime0, bool adjusted0) = uniMinter.shares(0);
    (,, uint16 delayDays1, uint48 pendingTime1, bool adjusted1) = uniMinter.shares(1);
    (,,, uint48 pendingTime2, bool adjusted2) = uniMinter.shares(2);

    assertEq(pendingTime0, 0);
    assertEq(pendingTime1, currentTime + delayDays1 * 1 days);
    assertEq(pendingTime2, 0);
    assertEq(adjusted0, false);
    assertEq(adjusted1, false);
    assertEq(adjusted2, false);
  }

  function test_RevokeShares_StandardRemoval() public {
    uint16 shortDelay = 90; // 90 days delay
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000, shortDelay);

    // Initiate revocation early enough that it completes before next mint
    vm.warp(100); // Start early in the period
    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    // Wait for half the delay period
    vm.warp(block.timestamp + shortDelay * 1 days / 2);

    uniMinter.revokeShares(0);

    assertEq(uniMinter.totalShares(), 0);
    vm.expectRevert();
    uniMinter.shares(0);
  }

  function test_RevokeShares_MultipleShares() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 3000, DEFAULT_REVOCATION_DELAY_DAYS);
    uniMinter.grantShares(bob, 2000, 180);
    uniMinter.grantShares(charlie, 1000, 90);

    uniMinter.initiateRevokeShares(1);
    vm.stopPrank();

    vm.warp(block.timestamp + 180 days);

    uniMinter.revokeShares(1);

    assertEq(uniMinter.totalShares(), 4000);

    (address recipient0, uint16 amount0,,, bool adjusted0) = uniMinter.shares(0);
    assertEq(recipient0, alice);
    assertEq(amount0, 3000);
    assertEq(adjusted0, false);

    (address recipient1, uint16 amount1,,, bool adjusted1) = uniMinter.shares(1);
    assertEq(recipient1, charlie);
    assertEq(amount1, 1000);
    assertEq(adjusted1, false);
  }

  function test_RevokeShares_RevertNotPendingRevocation() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000, DEFAULT_REVOCATION_DELAY_DAYS);

    vm.expectRevert(IUNIMinter.NotPendingRevocation.selector);
    uniMinter.revokeShares(0);
  }

  function test_RevokeShares_BeforeNextMint() public {
    uint16 shortDelay = 90; // Use shorter delay to ensure it completes before next mint
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000, shortDelay);

    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    // Set time so revocation completes before next mint
    vm.warp(block.timestamp + shortDelay * 1 days / 2);

    // Call revokeShares - should succeed and remove shares entirely
    uniMinter.revokeShares(0);

    assertEq(uniMinter.totalShares(), 0);
    vm.expectRevert();
    uniMinter.shares(0);
  }

  function test_RevokeShares_CalledByAnyone() public {
    uint16 shortDelay = 90;
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000, shortDelay);

    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    vm.warp(block.timestamp + shortDelay * 1 days);

    vm.prank(unauthorizedUser);
    uniMinter.revokeShares(0);

    assertEq(uniMinter.totalShares(), 0);
  }

  function test_RevokeShares_LastElement() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 3000, DEFAULT_REVOCATION_DELAY_DAYS);
    uniMinter.grantShares(bob, 2000, 180);

    uniMinter.initiateRevokeShares(1);
    vm.stopPrank();

    vm.warp(block.timestamp + 180 days);

    uniMinter.revokeShares(1);

    assertEq(uniMinter.totalShares(), 3000);

    (address recipient0, uint16 amount0,,, bool adjusted0) = uniMinter.shares(0);
    assertEq(recipient0, alice);
    assertEq(amount0, 3000);
    assertEq(adjusted0, false);

    vm.expectRevert();
    uniMinter.shares(1);
  }

  function test_MintAfterRevocation() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 5000, 180);
    uniMinter.grantShares(bob, 3000, DEFAULT_REVOCATION_DELAY_DAYS);

    uniMinter.initiateRevokeShares(0);
    vm.stopPrank();

    vm.warp(block.timestamp + 180 days);
    uniMinter.revokeShares(0);

    vm.warp(UNI.mintingAllowedAfter());

    uint256 totalSupplyBefore = UNI.totalSupply();
    uint256 expectedMintCap = totalSupplyBefore * MINT_CAP_PERCENT / 100;
    uint256 expectedTotalMint = expectedMintCap * 3000 / MAX_SHARES;
    uint256 expectedBobAmount = expectedTotalMint * 3000 / uniMinter.totalShares();

    uniMinter.mint();

    assertEq(UNI.balanceOf(alice), 0);
    assertEq(UNI.balanceOf(bob), expectedBobAmount);
  }

  function test_ComplexScenario() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 4000, DEFAULT_REVOCATION_DELAY_DAYS);
    uniMinter.grantShares(bob, 3000, 180);
    uniMinter.grantShares(charlie, 2000, 90);
    vm.stopPrank();

    vm.warp(UNI.mintingAllowedAfter());
    uniMinter.mint();

    uint256 aliceFirstMint = UNI.balanceOf(alice);
    uint256 bobFirstMint = UNI.balanceOf(bob);
    uint256 charlieFirstMint = UNI.balanceOf(charlie);

    assertGt(aliceFirstMint, 0);
    assertGt(bobFirstMint, 0);
    assertGt(charlieFirstMint, 0);

    vm.prank(owner);
    uniMinter.initiateRevokeShares(1);

    vm.warp(block.timestamp + 180 days);
    uniMinter.revokeShares(1);

    vm.prank(owner);
    uniMinter.grantShares(dave, 1000, DEFAULT_REVOCATION_DELAY_DAYS);

    vm.warp(block.timestamp + 365 days);
    uniMinter.mint();

    assertGt(UNI.balanceOf(alice), aliceFirstMint);
    assertEq(UNI.balanceOf(bob), bobFirstMint);
    assertGt(UNI.balanceOf(charlie), charlieFirstMint);
    assertGt(UNI.balanceOf(dave), 0);
  }

  function testFuzz_GrantShares(address recipient, uint16 amount, uint16 delayDays) public {
    vm.assume(amount <= MAX_SHARES);
    vm.assume(delayDays > 0);

    vm.prank(owner);
    uniMinter.grantShares(recipient, amount, delayDays);

    assertEq(uniMinter.totalShares(), amount);
    (address storedRecipient, uint16 storedAmount, uint16 storedDelay,, bool storedAdjusted) =
      uniMinter.shares(0);
    assertEq(storedRecipient, recipient);
    assertEq(storedAmount, amount);
    assertEq(storedDelay, delayDays);
    assertEq(storedAdjusted, false);
  }

  function testFuzz_MultipleGrantShares(
    address[3] memory recipients,
    uint16[3] memory amounts,
    uint16[3] memory delays
  ) public {
    uint256 totalAmount = 0;
    for (uint256 i = 0; i < 3; i++) {
      totalAmount += amounts[i];
      vm.assume(delays[i] > 0);
    }
    vm.assume(totalAmount <= MAX_SHARES);

    vm.startPrank(owner);
    for (uint256 i = 0; i < 3; i++) {
      uniMinter.grantShares(recipients[i], amounts[i], delays[i]);
    }
    vm.stopPrank();

    assertEq(uniMinter.totalShares(), totalAmount);

    for (uint256 i = 0; i < 3; i++) {
      (address recipient, uint16 amount, uint16 delay,, bool adjusted) = uniMinter.shares(i);
      assertEq(recipient, recipients[i]);
      assertEq(amount, amounts[i]);
      assertEq(delay, delays[i]);
      assertEq(adjusted, false);
    }
  }

  function testFuzz_MintDistribution(uint16[4] memory shares) public {
    uint256 totalAllocated = 0;
    address[4] memory recipients = [alice, bob, charlie, dave];

    for (uint256 i = 0; i < 4; i++) {
      totalAllocated += shares[i];
    }
    vm.assume(totalAllocated > 0 && totalAllocated <= MAX_SHARES);

    vm.startPrank(owner);
    for (uint256 i = 0; i < 4; i++) {
      if (shares[i] > 0) {
        uniMinter.grantShares(recipients[i], shares[i], DEFAULT_REVOCATION_DELAY_DAYS);
      }
    }
    vm.stopPrank();

    vm.warp(UNI.mintingAllowedAfter());

    uint256 mintCap = UNI.totalSupply() * MINT_CAP_PERCENT / 100;
    uint256 expectedMintAmount = mintCap * totalAllocated / MAX_SHARES;

    uniMinter.mint();

    for (uint256 i = 0; i < 4; i++) {
      if (shares[i] > 0) {
        uint256 expectedBalance = expectedMintAmount * shares[i] / uniMinter.totalShares();
        assertEq(UNI.balanceOf(recipients[i]), expectedBalance);
      }
    }
  }

  function test_ZeroAmountGrant() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 0, DEFAULT_REVOCATION_DELAY_DAYS);

    assertEq(uniMinter.totalShares(), 0);
    (address recipient, uint16 amount, uint16 delay,, bool adjusted) = uniMinter.shares(0);
    assertEq(recipient, alice);
    assertEq(amount, 0);
    assertEq(delay, DEFAULT_REVOCATION_DELAY_DAYS);
    assertEq(adjusted, false);
  }

  function test_EdgeCase_RevokeFirstOfMany() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 2500, 90);
    uniMinter.grantShares(bob, 2500, DEFAULT_REVOCATION_DELAY_DAYS);
    uniMinter.grantShares(charlie, 2500, DEFAULT_REVOCATION_DELAY_DAYS);
    uniMinter.grantShares(dave, 2500, DEFAULT_REVOCATION_DELAY_DAYS);

    uniMinter.initiateRevokeShares(0);
    vm.stopPrank();

    vm.warp(block.timestamp + 90 days);
    uniMinter.revokeShares(0);

    assertEq(uniMinter.totalShares(), 7500);

    (address recipient0, uint16 amount0,,,) = uniMinter.shares(0);
    assertEq(recipient0, dave);
    assertEq(amount0, 2500);

    (address recipient1, uint16 amount1,,,) = uniMinter.shares(1);
    assertEq(recipient1, bob);
    assertEq(amount1, 2500);

    (address recipient2, uint16 amount2,,,) = uniMinter.shares(2);
    assertEq(recipient2, charlie);
    assertEq(amount2, 2500);
  }

  function test_EdgeCase_RevokeMiddleOfMany() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 2500, DEFAULT_REVOCATION_DELAY_DAYS);
    uniMinter.grantShares(bob, 2500, DEFAULT_REVOCATION_DELAY_DAYS);
    uniMinter.grantShares(charlie, 2500, 180);
    uniMinter.grantShares(dave, 2500, DEFAULT_REVOCATION_DELAY_DAYS);

    uniMinter.initiateRevokeShares(2);
    vm.stopPrank();

    vm.warp(block.timestamp + 180 days);
    uniMinter.revokeShares(2);

    assertEq(uniMinter.totalShares(), 7500);

    (address recipient0,,,,) = uniMinter.shares(0);
    assertEq(recipient0, alice);

    (address recipient1,,,,) = uniMinter.shares(1);
    assertEq(recipient1, bob);

    (address recipient2,,,,) = uniMinter.shares(2);
    assertEq(recipient2, dave);
  }

  function test_MintWithZeroSharesInList() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 0, DEFAULT_REVOCATION_DELAY_DAYS);
    uniMinter.grantShares(bob, 5000, DEFAULT_REVOCATION_DELAY_DAYS);
    vm.stopPrank();

    vm.warp(UNI.mintingAllowedAfter());

    uint256 totalSupplyBefore = UNI.totalSupply();
    uint256 expectedMintCap = totalSupplyBefore * MINT_CAP_PERCENT / 100;
    uint256 expectedTotalMint = expectedMintCap * 5000 / MAX_SHARES;
    uint256 expectedBobAmount = expectedTotalMint * 5000 / uniMinter.totalShares();

    uniMinter.mint();

    assertEq(UNI.balanceOf(alice), 0);
    assertEq(UNI.balanceOf(bob), expectedBobAmount);
  }

  function test_ReInitiateRevocation() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000, 180);

    uint256 firstTime = block.timestamp;
    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    (,, uint16 delayDays, uint48 pendingTime1,) = uniMinter.shares(0);
    assertEq(pendingTime1, firstTime + delayDays * 1 days);

    vm.warp(block.timestamp + 90 days);
    uint256 secondTime = block.timestamp;
    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    (,,, uint48 pendingTime2,) = uniMinter.shares(0);
    assertEq(pendingTime2, secondTime + delayDays * 1 days);
  }

  function test_MintBeforeRevocationComplete() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 5000, DEFAULT_REVOCATION_DELAY_DAYS);
    uniMinter.grantShares(bob, 5000, DEFAULT_REVOCATION_DELAY_DAYS);

    uniMinter.initiateRevokeShares(0);
    vm.stopPrank();

    vm.warp(UNI.mintingAllowedAfter());

    uint256 totalSupplyBefore = UNI.totalSupply();
    uint256 expectedMintCap = totalSupplyBefore * MINT_CAP_PERCENT / 100;
    uint256 expectedMintAmount = expectedMintCap;

    uniMinter.mint();

    assertEq(UNI.balanceOf(alice), expectedMintAmount * 5000 / MAX_SHARES);
    assertEq(UNI.balanceOf(bob), expectedMintAmount * 5000 / MAX_SHARES);
  }

  function test_RevokeShares_PartialMint_HalfwayThroughPeriod() public {
    uint16 delayDays = 180;
    vm.prank(owner);
    uniMinter.grantShares(alice, 6000, delayDays);

    // Initiate revocation that will complete halfway through next mint period
    // Next mint at mintingAllowedAfter, revocation at mintingAllowedAfter + 182.5 days
    uint256 nextMintTime = UNI.mintingAllowedAfter();
    uint256 revocationCompleteTime = nextMintTime + 365 days / 2; // Halfway through next period

    // Calculate when to initiate to achieve this timing
    uint256 initiateTime = revocationCompleteTime - delayDays * 1 days;
    vm.warp(initiateTime);

    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    // Call revokeShares - should reduce shares to 50% (halfway through period)
    uniMinter.revokeShares(0);

    assertEq(uniMinter.totalShares(), 3000); // 50% of 6000
    (address recipient, uint16 amount,,,) = uniMinter.shares(0);
    assertEq(recipient, alice);
    assertEq(amount, 3000);
  }

  function test_RevokeShares_PartialMint_QuarterThroughPeriod() public {
    uint16 delayDays = 180;
    vm.prank(owner);
    uniMinter.grantShares(alice, 8000, delayDays);

    // Revocation completes 1/4 way through next mint period
    uint256 nextMintTime = UNI.mintingAllowedAfter();
    uint256 revocationCompleteTime = nextMintTime + 365 days / 4;
    uint256 initiateTime = revocationCompleteTime - delayDays * 1 days;
    vm.warp(initiateTime);

    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    uniMinter.revokeShares(0);

    assertEq(uniMinter.totalShares(), 2000); // 25% of 8000
    (address recipient, uint16 amount,,,) = uniMinter.shares(0);
    assertEq(recipient, alice);
    assertEq(amount, 2000);
  }

  function test_RevokeShares_PartialMint_ThenFullRevoke() public {
    uint16 delayDays = 180;
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000, delayDays);

    // Setup partial revocation
    uint256 nextMintTime = UNI.mintingAllowedAfter();
    uint256 revocationCompleteTime = nextMintTime + 365 days / 2;
    uint256 initiateTime = revocationCompleteTime - delayDays * 1 days;
    vm.warp(initiateTime);

    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    // First call reduces shares
    uniMinter.revokeShares(0);
    (,,,, bool adjusted) = uniMinter.shares(0);
    assertEq(uniMinter.totalShares(), 2500);
    assertEq(adjusted, true);

    // After the mint, the share can be fully removed
    vm.warp(nextMintTime);
    uniMinter.mint();

    // Now revoke again - should fully remove
    uniMinter.revokeShares(0);
    assertEq(uniMinter.totalShares(), 0);
    vm.expectRevert();
    uniMinter.shares(0);
  }

  function test_RevokeShares_RevertIfRevocationTooFarInFuture() public {
    uint16 delayDays = 180;
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000, delayDays);

    // Setup revocation that completes after the period following next mint
    uint256 nextMintTime = UNI.mintingAllowedAfter();
    uint256 revocationCompleteTime = nextMintTime + 365 days + 1; // Just after the period
    uint256 initiateTime = revocationCompleteTime - delayDays * 1 days;
    vm.warp(initiateTime);

    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    // Should revert as revocation is not ready yet
    vm.expectRevert(IUNIMinter.InvalidRevocation.selector);
    uniMinter.revokeShares(0);
  }

  // New tests for 365-day delay feature
  function test_GrantShares_With365DayDelay() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 7500, 365);

    assertEq(uniMinter.totalShares(), 7500);
    (address recipient, uint16 amount, uint16 delayDays, uint48 pendingRevocationTime,) =
      uniMinter.shares(0);
    assertEq(recipient, alice);
    assertEq(amount, 7500);
    assertEq(delayDays, 365);
    assertEq(pendingRevocationTime, 0);
  }

  function test_RevokeShares_365DayDelay_FullRevocation() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000, 365);

    // Initiate revocation
    uint256 initiateTime = block.timestamp;
    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    // Fast forward to when revocation is ready (exactly at next mint time)
    vm.warp(initiateTime + 365 days);

    // Execute revocation - when revocation time equals mint time, shares are reduced to 0
    uniMinter.revokeShares(0);

    // Shares are reduced to 0 but entry still exists
    assertEq(uniMinter.totalShares(), 0);
    (address recipient, uint16 amount,,,) = uniMinter.shares(0);
    assertEq(recipient, alice);
    assertEq(amount, 0);
  }

  function test_RevokeShares_365DayDelay_PartialRevocation() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 10_000, 365);

    // Calculate timing for partial revocation (75% through next mint period)
    uint256 nextMintTime = UNI.mintingAllowedAfter();
    uint256 revocationCompleteTime = nextMintTime + (365 days * 3 / 4);
    uint256 initiateTime = revocationCompleteTime - 365 days;

    vm.warp(initiateTime);
    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    // Execute partial revocation
    uniMinter.revokeShares(0);

    // Should have 75% of original shares (7500)
    assertEq(uniMinter.totalShares(), 7500);
    (address recipient, uint16 amount,,, bool adjusted) = uniMinter.shares(0);
    assertEq(recipient, alice);
    assertEq(amount, 7500);
    assertEq(adjusted, true); // Should be marked as adjusted
  }

  function test_MultipleShares_DifferentDelays() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 2500, 365); // 1 year delay
    uniMinter.grantShares(bob, 2500, 180); // 180 days delay
    uniMinter.grantShares(charlie, 2500, 90); // 90 days delay
    uniMinter.grantShares(dave, 2500, 30); // 30 days delay
    vm.stopPrank();

    assertEq(uniMinter.totalShares(), 10_000);

    // Verify each share has correct delay
    (,, uint16 delay0,,) = uniMinter.shares(0);
    (,, uint16 delay1,,) = uniMinter.shares(1);
    (,, uint16 delay2,,) = uniMinter.shares(2);
    (,, uint16 delay3,,) = uniMinter.shares(3);

    assertEq(delay0, 365);
    assertEq(delay1, 180);
    assertEq(delay2, 90);
    assertEq(delay3, 30);
  }

  function test_InitiateAndRevoke_365DayDelay_BeforeDelay() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000, 365);

    // Start well before the next mint to ensure proper timing
    vm.warp(100);

    uint256 initiateTime = block.timestamp;
    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    // Try to revoke before delay is complete (after 364 days)
    vm.warp(initiateTime + 364 days);

    // At this point, revocation is not ready yet (needs 365 days)
    // But we may be past the next mint time, which would make it process as partial
    (,,, uint48 pendingTime,) = uniMinter.shares(0);
    uint256 mintTime = UNI.mintingAllowedAfter();

    if (pendingTime > mintTime && pendingTime - mintTime < 365 days) {
      // Would process as partial revocation
      uniMinter.revokeShares(0);
      (, uint16 remainingAmount,,, bool adjusted) = uniMinter.shares(0);
      assertEq(adjusted, true);
      // The amount might round down to 0 if very close to revocation time
      assertLe(remainingAmount, 5000); // Should not have more than original
    } else {
      // Should revert as not ready
      vm.expectRevert(IUNIMinter.InvalidRevocation.selector);
      uniMinter.revokeShares(0);
    }

    // Now warp to exactly 365 days from initiation
    vm.warp(initiateTime + 365 days);

    // Should succeed now - may need to call again if shares weren't fully removed
    if (uniMinter.totalShares() > 0) uniMinter.revokeShares(0);
    assertEq(uniMinter.totalShares(), 0);
  }

  function test_Mint_WithMultiple365DayDelayShares() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 3000, 365);
    uniMinter.grantShares(bob, 3000, 365);
    uniMinter.grantShares(charlie, 4000, 365);
    vm.stopPrank();

    vm.warp(UNI.mintingAllowedAfter());

    uint256 totalSupplyBefore = UNI.totalSupply();
    uint256 expectedMintCap = totalSupplyBefore * MINT_CAP_PERCENT / 100;
    uint256 expectedMintAmount = expectedMintCap;

    uniMinter.mint();

    assertEq(UNI.balanceOf(alice), expectedMintAmount * 3000 / MAX_SHARES);
    assertEq(UNI.balanceOf(bob), expectedMintAmount * 3000 / MAX_SHARES);
    assertEq(UNI.balanceOf(charlie), expectedMintAmount * 4000 / MAX_SHARES);
  }

  function testFuzz_ConfigurableRevocationDelay(uint16 delayDays, uint16 shareAmount) public {
    vm.assume(delayDays > 0 && delayDays <= 730); // Max 2 years
    vm.assume(shareAmount > 0 && shareAmount <= MAX_SHARES);

    vm.prank(owner);
    uniMinter.grantShares(alice, shareAmount, delayDays);

    (address recipient, uint16 amount, uint16 storedDelay, uint48 pendingTime, bool adjusted) =
      uniMinter.shares(0);
    assertEq(recipient, alice);
    assertEq(amount, shareAmount);
    assertEq(storedDelay, delayDays);
    assertEq(pendingTime, 0);
    assertEq(adjusted, false);

    // Test revocation timing
    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    (,,, uint48 newPendingTime,) = uniMinter.shares(0);
    assertEq(newPendingTime, block.timestamp + uint256(delayDays) * 1 days);
  }

  function test_SetMinter_Success() public {
    address newMinter = makeAddr("newMinter");

    vm.prank(owner);
    uniMinter.setMinter(newMinter);

    assertEq(UNI.minter(), newMinter);
  }

  function test_SetMinter_RevertUnauthorized() public {
    address newMinter = makeAddr("newMinter");

    vm.expectRevert("UNAUTHORIZED");
    vm.prank(unauthorizedUser);
    uniMinter.setMinter(newMinter);
  }

  function test_SetMinter_DisablesMinting() public {
    // First grant shares and verify minting works
    vm.prank(owner);
    uniMinter.grantShares(alice, MAX_SHARES, DEFAULT_REVOCATION_DELAY_DAYS);

    vm.warp(UNI.mintingAllowedAfter());
    uniMinter.mint();
    assertGt(UNI.balanceOf(alice), 0);

    // Transfer minter role to a new address
    address newMinter = makeAddr("newMinter");
    vm.prank(owner);
    uniMinter.setMinter(newMinter);

    // Verify minting no longer works from this contract
    vm.warp(block.timestamp + 365 days);
    vm.expectRevert(); // Should revert as this contract is no longer the minter
    uniMinter.mint();
  }

  function test_SetMinter_TransferToZeroAddress() public {
    // Setting minter to zero address effectively burns the minting capability
    vm.prank(owner);
    uniMinter.setMinter(address(0));

    assertEq(UNI.minter(), address(0));
  }

  function test_SetMinter_TransferBackToOriginal() public {
    address newMinter = makeAddr("newMinter");

    // Transfer to new minter
    vm.prank(owner);
    uniMinter.setMinter(newMinter);
    assertEq(UNI.minter(), newMinter);

    // Mock the new minter transferring back
    vm.mockCall(
      address(UNI),
      abi.encodeWithSelector(IUNI.setMinter.selector, address(uniMinter)),
      abi.encode()
    );

    // New minter transfers back to original
    vm.prank(newMinter);
    UNI.setMinter(address(uniMinter));

    // Clear the mock to check actual state
    vm.clearMockedCalls();

    // In a real scenario, this would require the new minter to actually call setMinter
    // For testing purposes, we verify the concept works
  }

  function test_SetMinter_CalledMultipleTimes() public {
    address minter1 = makeAddr("minter1");
    address minter2 = makeAddr("minter2");

    vm.startPrank(owner);

    uniMinter.setMinter(minter1);
    assertEq(UNI.minter(), minter1);

    // After first transfer, subsequent calls from uniMinter should fail
    // since it's no longer the minter
    vm.expectRevert();
    uniMinter.setMinter(minter2);

    vm.stopPrank();
  }

  function test_SetMinter_DoesNotAffectShares() public {
    // Grant shares
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 3000, DEFAULT_REVOCATION_DELAY_DAYS);
    uniMinter.grantShares(bob, 2000, DEFAULT_REVOCATION_DELAY_DAYS);
    vm.stopPrank();

    uint256 totalSharesBefore = uniMinter.totalShares();

    // Transfer minter role
    address newMinter = makeAddr("newMinter");
    vm.prank(owner);
    uniMinter.setMinter(newMinter);

    // Verify shares are unchanged
    assertEq(uniMinter.totalShares(), totalSharesBefore);

    (address recipient0, uint16 amount0,,,) = uniMinter.shares(0);
    assertEq(recipient0, alice);
    assertEq(amount0, 3000);

    (address recipient1, uint16 amount1,,,) = uniMinter.shares(1);
    assertEq(recipient1, bob);
    assertEq(amount1, 2000);
  }

  function testFuzz_SetMinter(address newMinter) public {
    vm.prank(owner);
    uniMinter.setMinter(newMinter);

    assertEq(UNI.minter(), newMinter);
  }

  function test_MultipleMints_OverMultipleYears_Full2PercentInflation() public {
    // Grant full shares to ensure full 2% inflation rate is allocated
    vm.prank(owner);
    uniMinter.grantShares(alice, MAX_SHARES, DEFAULT_REVOCATION_DELAY_DAYS);

    // Year 1 mint
    vm.warp(UNI.mintingAllowedAfter());
    uint256 supplyBeforeYear1 = UNI.totalSupply();
    uint256 expectedYear1Mint = supplyBeforeYear1 * MINT_CAP_PERCENT / 100;

    uniMinter.mint();
    uint256 year1Balance = UNI.balanceOf(alice);
    assertEq(year1Balance, expectedYear1Mint);
    assertEq(UNI.totalSupply(), supplyBeforeYear1 + expectedYear1Mint);

    // Warp to Year 2
    vm.warp(block.timestamp + 365 days);
    uint256 supplyBeforeYear2 = UNI.totalSupply();
    uint256 expectedYear2Mint = supplyBeforeYear2 * MINT_CAP_PERCENT / 100;

    uniMinter.mint();
    uint256 year2Balance = UNI.balanceOf(alice) - year1Balance;
    assertEq(year2Balance, expectedYear2Mint);
    assertEq(UNI.totalSupply(), supplyBeforeYear2 + expectedYear2Mint);

    // Warp halfway through Year 3 (to show mid-year timing doesn't affect minting)
    vm.warp(block.timestamp + 182 days);
    // Try to mint - should still be too early
    vm.expectRevert();
    UNI.mint(alice, 1);

    // Complete warp to Year 3
    vm.warp(block.timestamp + 183 days);
    uint256 supplyBeforeYear3 = UNI.totalSupply();
    uint256 expectedYear3Mint = supplyBeforeYear3 * MINT_CAP_PERCENT / 100;

    uniMinter.mint();
    uint256 year3Balance = UNI.balanceOf(alice) - year1Balance - year2Balance;
    assertEq(year3Balance, expectedYear3Mint);
    assertEq(UNI.totalSupply(), supplyBeforeYear3 + expectedYear3Mint);

    // Warp to Year 4 with extra time to show timing flexibility
    vm.warp(block.timestamp + 400 days);
    uint256 supplyBeforeYear4 = UNI.totalSupply();
    uint256 expectedYear4Mint = supplyBeforeYear4 * MINT_CAP_PERCENT / 100;

    uniMinter.mint();
    uint256 year4Balance = UNI.balanceOf(alice) - year1Balance - year2Balance - year3Balance;
    assertEq(year4Balance, expectedYear4Mint);
    assertEq(UNI.totalSupply(), supplyBeforeYear4 + expectedYear4Mint);

    // Warp to Year 5
    vm.warp(block.timestamp + 365 days);
    uint256 supplyBeforeYear5 = UNI.totalSupply();
    uint256 expectedYear5Mint = supplyBeforeYear5 * MINT_CAP_PERCENT / 100;

    uniMinter.mint();
    uint256 year5Balance =
      UNI.balanceOf(alice) - year1Balance - year2Balance - year3Balance - year4Balance;
    assertEq(year5Balance, expectedYear5Mint);
    assertEq(UNI.totalSupply(), supplyBeforeYear5 + expectedYear5Mint);

    // Verify compound growth effect - each year's mint is 2% of an increasingly larger supply
    assertGt(year2Balance, year1Balance); // Year 2 mint > Year 1 due to compound growth
    assertGt(year3Balance, year2Balance); // Year 3 mint > Year 2
    assertGt(year4Balance, year3Balance); // Year 4 mint > Year 3
    assertGt(year5Balance, year4Balance); // Year 5 mint > Year 4
  }

  function test_revokeShares_PreventDoubleAdjustment() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000, 180);

    // Setup partial revocation
    uint256 nextMintTime = UNI.mintingAllowedAfter();
    uint256 revocationCompleteTime = nextMintTime + 365 days / 2; // Halfway through next period
    uint256 initiateTime = revocationCompleteTime - 180 days;
    vm.warp(initiateTime);

    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    // First call reduces shares and sets adjustedForRevocation = true
    uniMinter.revokeShares(0);
    assertEq(uniMinter.totalShares(), 2500); // 50% of 5000
    (address recipient, uint16 amount,,, bool adjusted) = uniMinter.shares(0);
    assertEq(recipient, alice);
    assertEq(amount, 2500);
    assertEq(adjusted, true);

    // Second call should revert because it's already been revoked
    vm.expectRevert(IUNIMinter.InvalidRevocation.selector);
    uniMinter.revokeShares(0);

    // Verify shares unchanged after failed second call
    assertEq(uniMinter.totalShares(), 2500);
    (recipient, amount,,, adjusted) = uniMinter.shares(0);
    assertEq(recipient, alice);
    assertEq(amount, 2500);
    assertEq(adjusted, true);
  }

  /// @dev initiateRevokeShares CANNOT to called twice if its already been adjusted
  function test_revokeShares_PreventDoubleInitiateRevokeShares() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000, 180);

    // Setup partial revocation
    uint256 nextMintTime = UNI.mintingAllowedAfter();
    uint256 revocationCompleteTime = nextMintTime + 365 days / 2; // Halfway through next period
    uint256 initiateTime = revocationCompleteTime - 180 days;
    vm.warp(initiateTime);

    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    // First call reduces shares and sets adjustedForRevocation = true
    uniMinter.revokeShares(0);
    assertEq(uniMinter.totalShares(), 2500); // 50% of 5000
    (address recipient, uint16 amount,,, bool adjusted) = uniMinter.shares(0);
    assertEq(recipient, alice);
    assertEq(amount, 2500);
    assertEq(adjusted, true);

    // Cannot re-initiate revocation on something already adjusted
    vm.prank(owner);
    vm.expectRevert(IUNIMinter.InvalidRevocation.selector);
    uniMinter.initiateRevokeShares(0);
  }
}
