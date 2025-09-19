pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {UniVesting} from "../src/UniVesting.sol";
import {IUNI} from "../src/interfaces/IUNI.sol";

import {console2} from "forge-std/console2.sol";

contract VestingTest is Test {
  MockERC20 public vestingToken;
  UniVesting public vesting;

  uint256 public constant INITIAL_TOKEN_AMOUNT = 1000e18;

  function setUp() public {
    vestingToken = new MockERC20("VestingToken", "VTK", 18);

    vm.mockCall(
      address(vestingToken),
      abi.encodeWithSelector(IUNI.mintingAllowedAfter.selector),
      abi.encode(block.timestamp - 1)
    );

    vm.mockCall(
      address(vestingToken),
      abi.encodeWithSelector(IUNI.minimumTimeBetweenMints.selector),
      abi.encode(365 days)
    );

    vesting = new UniVesting(address(vestingToken), 30 days);
  }

  function test_start_reverts_whenMintingWindowNotChanged() public {
    vm.expectRevert(UniVesting.MintingWindowClosed.selector);
    vesting.start();
  }

  function test_start() public {
    _mockMintAt(block.timestamp, INITIAL_TOKEN_AMOUNT);
    assertEq(vestingToken.balanceOf(address(vesting)), INITIAL_TOKEN_AMOUNT);

    vesting.start();

    assertEq(vesting.claimed(), 0);
    assertEq(vesting.amountVesting(), INITIAL_TOKEN_AMOUNT);
    assertEq(vesting.startTime(), block.timestamp);
    assertEq(vesting.mintingAllowedAfterCheckpoint(), block.timestamp);
    assertEq(vesting.totalVested(), 0);
    assertEq(vesting.claimable(), 0);
  }

  function test_claim() public {
    _mockMintAt(block.timestamp, INITIAL_TOKEN_AMOUNT);

    vesting.start();
    assertEq(vesting.totalVested(), 0);
    assertEq(vesting.claimed(), 0);
    assertEq(vesting.claimable(), 0);

    /// Even after an attempt to claim no state is changed.
    vesting.claim();
    assertEq(vesting.totalVested(), 0);
    assertEq(vesting.claimed(), 0);
    assertEq(vesting.claimable(), 0);
    assertEq(vestingToken.balanceOf(address(vesting)), INITIAL_TOKEN_AMOUNT);
  }

  function test_claim_after_1_period() public {
    _mockMintAt(block.timestamp, INITIAL_TOKEN_AMOUNT);

    vesting.start();
    vm.warp(block.timestamp + 30 days);
    /// Total vested should be 1/numPeriods of the inital amount (ie 1/12)
    uint256 expectedTotalVested = INITIAL_TOKEN_AMOUNT / vesting.totalPeriods();
    assertEq(vesting.totalVested(), expectedTotalVested);
    assertEq(vesting.claimed(), 0);
    assertEq(vesting.claimable(), expectedTotalVested);

    vesting.claim();
    assertEq(vesting.totalVested(), expectedTotalVested);
    assertEq(vesting.claimed(), SafeCast.toInt256(expectedTotalVested));
    assertEq(vesting.claimable(), 0);
  }

  function test_start_with_leftover() public {
    _mockMintAt(block.timestamp, INITIAL_TOKEN_AMOUNT);

    vesting.start();
    uint256 newTime = block.timestamp + vesting.totalVestingPeriod();
    vm.warp(newTime);
    /// Total vested should be the full amount.
    uint256 expectedTotalVested = INITIAL_TOKEN_AMOUNT;
    assertEq(vesting.totalVested(), expectedTotalVested);
    assertEq(vesting.claimed(), 0);
    assertEq(vesting.claimable(), expectedTotalVested);

    /// Without calling claim, we should be able to start a new vest (assuming a new mint has
    /// happened).
    _mockMintAt(newTime, INITIAL_TOKEN_AMOUNT * 2);
    vesting.start();

    /// The leftover tokens from the previous vest are cached in the claimed amount.
    assertEq(vesting.claimed(), -SafeCast.toInt256(INITIAL_TOKEN_AMOUNT));
    assertEq(vesting.amountVesting(), INITIAL_TOKEN_AMOUNT * 2);
    assertEq(vesting.startTime(), newTime);
    assertEq(vesting.mintingAllowedAfterCheckpoint(), newTime);
    assertEq(vesting.totalVested(), 0);
    assertEq(vesting.claimable(), INITIAL_TOKEN_AMOUNT);
  }

  function test_claim_with_leftover() public {
    /// Start first vesting window.addmod
    _mockMintAt(block.timestamp, INITIAL_TOKEN_AMOUNT);
    vesting.start();

    /// Warp to the end of the first vesting window, without a claim. The total inital amount will
    /// be vested.
    uint256 newTime = block.timestamp + vesting.totalVestingPeriod();
    vm.warp(newTime);
    uint256 expectedTotalVested = INITIAL_TOKEN_AMOUNT;
    assertEq(vesting.totalVested(), expectedTotalVested);
    assertEq(vesting.claimed(), 0);
    assertEq(vesting.claimable(), expectedTotalVested);
    assertEq(vesting.amountVesting(), INITIAL_TOKEN_AMOUNT);

    /// Without calling claim, we should be able to start a new vest (assuming a new mint has
    /// happened).
    _mockMintAt(newTime, INITIAL_TOKEN_AMOUNT * 2);
    vesting.start();

    assertEq(vesting.totalVested(), 0);
    assertEq(vesting.claimable(), INITIAL_TOKEN_AMOUNT);
    assertEq(vesting.amountVesting(), INITIAL_TOKEN_AMOUNT * 2);
    assertEq(vesting.claimed(), -SafeCast.toInt256(INITIAL_TOKEN_AMOUNT));
    /// This is the leftover amount from the previous vest.

    /// Calling claim should only take the leftover tokens from the previous vest.
    vesting.claim();
    assertEq(vesting.claimable(), 0);
    /// The claimed amount is 0 because the claim call only took tokens from the previous vest.
    assertEq(vesting.claimed(), 0);
    assertEq(vesting.amountVesting(), INITIAL_TOKEN_AMOUNT * 2);
    assertEq(vesting.totalVested(), 0);
  }

  function _mockMintAt(uint256 timestamp, uint256 mintAmount) public {
    /// Update the mintingAllowedAfter timestamp.
    vm.mockCall(
      address(vestingToken),
      abi.encodeWithSelector(IUNI.mintingAllowedAfter.selector),
      abi.encode(timestamp)
    );

    vestingToken.mint(address(vesting), mintAmount);
  }
}
