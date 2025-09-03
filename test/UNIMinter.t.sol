// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";

import {UNIMinter} from "../src/UNIMinter.sol";
import {MockUNIToken} from "./mocks/MockUNIToken.sol";

contract UNIMinterTest is Test {
  UNIMinter public uniMinter;
  MockUNIToken public UNI;

  address public owner = makeAddr("owner");
  address public alice = makeAddr("alice");
  address public bob = makeAddr("bob");
  address public charlie = makeAddr("charlie");
  address public dave = makeAddr("dave");
  address public unauthorizedUser = makeAddr("UnauthorizedUser");

  uint48 constant REVOCATION_DELAY = 180 days;
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
    uniMinter.grantShares(alice, 5000);

    assertEq(uniMinter.totalShares(), 5000);
    (address recipient, uint16 amount, uint48 pendingRevocationTime) = uniMinter.shares(0);
    assertEq(recipient, alice);
    assertEq(amount, 5000);
    assertEq(pendingRevocationTime, 0);
  }

  function test_GrantShares_Multiple() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 3000);
    uniMinter.grantShares(bob, 2000);
    uniMinter.grantShares(charlie, 1500);
    vm.stopPrank();

    assertEq(uniMinter.totalShares(), 6500);

    (address recipient0, uint16 amount0,) = uniMinter.shares(0);
    assertEq(recipient0, alice);
    assertEq(amount0, 3000);

    (address recipient1, uint16 amount1,) = uniMinter.shares(1);
    assertEq(recipient1, bob);
    assertEq(amount1, 2000);

    (address recipient2, uint16 amount2,) = uniMinter.shares(2);
    assertEq(recipient2, charlie);
    assertEq(amount2, 1500);
  }

  function test_GrantShares_MaxShares() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, MAX_SHARES);
    assertEq(uniMinter.totalShares(), MAX_SHARES);
  }

  function test_GrantShares_RevertInsufficientShares() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 6000);

    vm.expectRevert(UNIMinter.InsufficientShares.selector);
    uniMinter.grantShares(bob, 5000);
    vm.stopPrank();
  }

  function test_GrantShares_RevertUnauthorized() public {
    vm.expectRevert("UNAUTHORIZED");
    vm.prank(unauthorizedUser);
    uniMinter.grantShares(alice, 5000);
  }

  function test_GrantShares_SameRecipientMultipleTimes() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 2000);
    uniMinter.grantShares(alice, 3000);
    vm.stopPrank();

    assertEq(uniMinter.totalShares(), 5000);

    (address recipient0, uint16 amount0,) = uniMinter.shares(0);
    assertEq(recipient0, alice);
    assertEq(amount0, 2000);

    (address recipient1, uint16 amount1,) = uniMinter.shares(1);
    assertEq(recipient1, alice);
    assertEq(amount1, 3000);
  }

  function test_Mint_SingleRecipientFullShares() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, MAX_SHARES);

    vm.warp(UNI.mintingAllowedAfter());

    uint256 expectedMintAmount = UNI.totalSupply() * MINT_CAP_PERCENT / 100;

    vm.expectEmit(true, true, false, true);
    emit Transfer(address(0), address(uniMinter), expectedMintAmount);

    uniMinter.mint();

    assertEq(UNI.balanceOf(alice), expectedMintAmount);
    assertEq(UNI.totalSupply(), UNI.initialTotalSupply() + expectedMintAmount);
  }

  function test_Mint_MultipleRecipients() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 5000);
    uniMinter.grantShares(bob, 3000);
    uniMinter.grantShares(charlie, 2000);
    vm.stopPrank();

    vm.warp(UNI.mintingAllowedAfter());

    uint256 totalSupplyBefore = UNI.totalSupply();
    uint256 expectedMintCap = totalSupplyBefore * MINT_CAP_PERCENT / 100;
    uint256 expectedMintAmount = expectedMintCap * MAX_SHARES / MAX_SHARES;

    uniMinter.mint();

    assertEq(UNI.balanceOf(alice), expectedMintAmount * 5000 / MAX_SHARES);
    assertEq(UNI.balanceOf(bob), expectedMintAmount * 3000 / MAX_SHARES);
    assertEq(UNI.balanceOf(charlie), expectedMintAmount * 2000 / MAX_SHARES);
    assertEq(UNI.totalSupply(), totalSupplyBefore + expectedMintAmount);
  }

  function test_Mint_PartialShares() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000);

    vm.warp(UNI.mintingAllowedAfter());

    uint256 totalSupplyBefore = UNI.totalSupply();
    uint256 expectedMintCap = totalSupplyBefore * MINT_CAP_PERCENT / 100;
    uint256 expectedTotalMint = expectedMintCap * 5000 / MAX_SHARES;
    uint256 expectedAliceAmount = expectedTotalMint * 5000 / MAX_SHARES;

    uniMinter.mint();

    assertEq(UNI.balanceOf(alice), expectedAliceAmount);
    assertEq(UNI.totalSupply(), totalSupplyBefore + expectedTotalMint);
  }

  function test_Mint_RevertNoShares() public {
    vm.warp(UNI.mintingAllowedAfter());

    vm.expectRevert(UNIMinter.NoShares.selector);
    uniMinter.mint();
  }

  function test_Mint_CalledByAnyone() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000);

    vm.warp(UNI.mintingAllowedAfter());

    vm.prank(unauthorizedUser);
    uniMinter.mint();

    assertGt(UNI.balanceOf(alice), 0);
  }

  function test_Mint_ConsecutiveMints() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, MAX_SHARES);

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
    uniMinter.grantShares(alice, 5000);

    uint256 currentTime = block.timestamp;
    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    (,, uint48 pendingRevocationTime) = uniMinter.shares(0);
    assertEq(pendingRevocationTime, currentTime + REVOCATION_DELAY);
  }

  function test_InitiateRevokeShares_RevertUnauthorized() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000);

    vm.expectRevert("UNAUTHORIZED");
    vm.prank(unauthorizedUser);
    uniMinter.initiateRevokeShares(0);
  }

  function test_InitiateRevokeShares_MultipleShares() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 3000);
    uniMinter.grantShares(bob, 2000);
    uniMinter.grantShares(charlie, 1000);

    uint256 currentTime = block.timestamp;
    uniMinter.initiateRevokeShares(1);
    vm.stopPrank();

    (,, uint48 pendingTime0) = uniMinter.shares(0);
    (,, uint48 pendingTime1) = uniMinter.shares(1);
    (,, uint48 pendingTime2) = uniMinter.shares(2);

    assertEq(pendingTime0, 0);
    assertEq(pendingTime1, currentTime + REVOCATION_DELAY);
    assertEq(pendingTime2, 0);
  }

  function test_RevokeShares_AfterDelay() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000);

    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    vm.warp(block.timestamp + REVOCATION_DELAY);

    uniMinter.revokeShares(0);

    assertEq(uniMinter.totalShares(), 0);
    vm.expectRevert();
    uniMinter.shares(0);
  }

  function test_RevokeShares_MultipleShares() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 3000);
    uniMinter.grantShares(bob, 2000);
    uniMinter.grantShares(charlie, 1000);

    uniMinter.initiateRevokeShares(1);
    vm.stopPrank();

    vm.warp(block.timestamp + REVOCATION_DELAY);

    uniMinter.revokeShares(1);

    assertEq(uniMinter.totalShares(), 4000);

    (address recipient0, uint16 amount0,) = uniMinter.shares(0);
    assertEq(recipient0, alice);
    assertEq(amount0, 3000);

    (address recipient1, uint16 amount1,) = uniMinter.shares(1);
    assertEq(recipient1, charlie);
    assertEq(amount1, 1000);
  }

  function test_RevokeShares_RevertNotPendingRevocation() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000);

    vm.expectRevert(UNIMinter.NotPendingRevocation.selector);
    uniMinter.revokeShares(0);
  }

  function test_RevokeShares_RevertRevocationNotReady() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000);

    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    vm.warp(block.timestamp + REVOCATION_DELAY - 1);

    vm.expectRevert(UNIMinter.RevocationNotReady.selector);
    uniMinter.revokeShares(0);
  }

  function test_RevokeShares_CalledByAnyone() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000);

    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    vm.warp(block.timestamp + REVOCATION_DELAY);

    vm.prank(unauthorizedUser);
    uniMinter.revokeShares(0);

    assertEq(uniMinter.totalShares(), 0);
  }

  function test_RevokeShares_LastElement() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 3000);
    uniMinter.grantShares(bob, 2000);

    uniMinter.initiateRevokeShares(1);
    vm.stopPrank();

    vm.warp(block.timestamp + REVOCATION_DELAY);

    uniMinter.revokeShares(1);

    assertEq(uniMinter.totalShares(), 3000);

    (address recipient0, uint16 amount0,) = uniMinter.shares(0);
    assertEq(recipient0, alice);
    assertEq(amount0, 3000);

    vm.expectRevert();
    uniMinter.shares(1);
  }

  function test_MintAfterRevocation() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 5000);
    uniMinter.grantShares(bob, 3000);

    uniMinter.initiateRevokeShares(0);
    vm.stopPrank();

    vm.warp(block.timestamp + REVOCATION_DELAY);
    uniMinter.revokeShares(0);

    vm.warp(UNI.mintingAllowedAfter());

    uint256 totalSupplyBefore = UNI.totalSupply();
    uint256 expectedMintCap = totalSupplyBefore * MINT_CAP_PERCENT / 100;
    uint256 expectedTotalMint = expectedMintCap * 3000 / MAX_SHARES;
    uint256 expectedBobAmount = expectedTotalMint * 3000 / MAX_SHARES;

    uniMinter.mint();

    assertEq(UNI.balanceOf(alice), 0);
    assertEq(UNI.balanceOf(bob), expectedBobAmount);
  }

  function test_ComplexScenario() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 4000);
    uniMinter.grantShares(bob, 3000);
    uniMinter.grantShares(charlie, 2000);
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

    vm.warp(block.timestamp + REVOCATION_DELAY);
    uniMinter.revokeShares(1);

    vm.prank(owner);
    uniMinter.grantShares(dave, 1000);

    vm.warp(block.timestamp + 365 days);
    uniMinter.mint();

    assertGt(UNI.balanceOf(alice), aliceFirstMint);
    assertEq(UNI.balanceOf(bob), bobFirstMint);
    assertGt(UNI.balanceOf(charlie), charlieFirstMint);
    assertGt(UNI.balanceOf(dave), 0);
  }

  function testFuzz_GrantShares(address recipient, uint16 amount) public {
    vm.assume(amount <= MAX_SHARES);

    vm.prank(owner);
    uniMinter.grantShares(recipient, amount);

    assertEq(uniMinter.totalShares(), amount);
    (address storedRecipient, uint16 storedAmount,) = uniMinter.shares(0);
    assertEq(storedRecipient, recipient);
    assertEq(storedAmount, amount);
  }

  function testFuzz_MultipleGrantShares(address[3] memory recipients, uint16[3] memory amounts)
    public
  {
    uint256 totalAmount = 0;
    for (uint256 i = 0; i < 3; i++) {
      totalAmount += amounts[i];
    }
    vm.assume(totalAmount <= MAX_SHARES);

    vm.startPrank(owner);
    for (uint256 i = 0; i < 3; i++) {
      uniMinter.grantShares(recipients[i], amounts[i]);
    }
    vm.stopPrank();

    assertEq(uniMinter.totalShares(), totalAmount);

    for (uint256 i = 0; i < 3; i++) {
      (address recipient, uint16 amount,) = uniMinter.shares(i);
      assertEq(recipient, recipients[i]);
      assertEq(amount, amounts[i]);
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
      if (shares[i] > 0) uniMinter.grantShares(recipients[i], shares[i]);
    }
    vm.stopPrank();

    vm.warp(UNI.mintingAllowedAfter());

    uint256 mintCap = UNI.totalSupply() * MINT_CAP_PERCENT / 100;
    uint256 expectedMintAmount = mintCap * totalAllocated / MAX_SHARES;

    uniMinter.mint();

    for (uint256 i = 0; i < 4; i++) {
      if (shares[i] > 0) {
        uint256 expectedBalance = expectedMintAmount * shares[i] / MAX_SHARES;
        assertEq(UNI.balanceOf(recipients[i]), expectedBalance);
      }
    }
  }

  function test_ZeroAmountGrant() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 0);

    assertEq(uniMinter.totalShares(), 0);
    (address recipient, uint16 amount,) = uniMinter.shares(0);
    assertEq(recipient, alice);
    assertEq(amount, 0);
  }

  function test_EdgeCase_RevokeFirstOfMany() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 2500);
    uniMinter.grantShares(bob, 2500);
    uniMinter.grantShares(charlie, 2500);
    uniMinter.grantShares(dave, 2500);

    uniMinter.initiateRevokeShares(0);
    vm.stopPrank();

    vm.warp(block.timestamp + REVOCATION_DELAY);
    uniMinter.revokeShares(0);

    assertEq(uniMinter.totalShares(), 7500);

    (address recipient0, uint16 amount0,) = uniMinter.shares(0);
    assertEq(recipient0, dave);
    assertEq(amount0, 2500);

    (address recipient1, uint16 amount1,) = uniMinter.shares(1);
    assertEq(recipient1, bob);
    assertEq(amount1, 2500);

    (address recipient2, uint16 amount2,) = uniMinter.shares(2);
    assertEq(recipient2, charlie);
    assertEq(amount2, 2500);
  }

  function test_EdgeCase_RevokeMiddleOfMany() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 2500);
    uniMinter.grantShares(bob, 2500);
    uniMinter.grantShares(charlie, 2500);
    uniMinter.grantShares(dave, 2500);

    uniMinter.initiateRevokeShares(2);
    vm.stopPrank();

    vm.warp(block.timestamp + REVOCATION_DELAY);
    uniMinter.revokeShares(2);

    assertEq(uniMinter.totalShares(), 7500);

    (address recipient0,,) = uniMinter.shares(0);
    assertEq(recipient0, alice);

    (address recipient1,,) = uniMinter.shares(1);
    assertEq(recipient1, bob);

    (address recipient2,,) = uniMinter.shares(2);
    assertEq(recipient2, dave);
  }

  function test_MintWithZeroSharesInList() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 0);
    uniMinter.grantShares(bob, 5000);
    vm.stopPrank();

    vm.warp(UNI.mintingAllowedAfter());

    uint256 totalSupplyBefore = UNI.totalSupply();
    uint256 expectedMintCap = totalSupplyBefore * MINT_CAP_PERCENT / 100;
    uint256 expectedTotalMint = expectedMintCap * 5000 / MAX_SHARES;
    uint256 expectedBobAmount = expectedTotalMint * 5000 / MAX_SHARES;

    uniMinter.mint();

    assertEq(UNI.balanceOf(alice), 0);
    assertEq(UNI.balanceOf(bob), expectedBobAmount);
  }

  function test_ReInitiateRevocation() public {
    vm.prank(owner);
    uniMinter.grantShares(alice, 5000);

    uint256 firstTime = block.timestamp;
    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    (,, uint48 pendingTime1) = uniMinter.shares(0);
    assertEq(pendingTime1, firstTime + REVOCATION_DELAY);

    vm.warp(block.timestamp + 90 days);
    uint256 secondTime = block.timestamp;
    vm.prank(owner);
    uniMinter.initiateRevokeShares(0);

    (,, uint48 pendingTime2) = uniMinter.shares(0);
    assertEq(pendingTime2, secondTime + REVOCATION_DELAY);
  }

  function test_MintBeforeRevocationComplete() public {
    vm.startPrank(owner);
    uniMinter.grantShares(alice, 5000);
    uniMinter.grantShares(bob, 5000);

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
}
