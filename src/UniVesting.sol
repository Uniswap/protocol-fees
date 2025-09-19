// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IUNI} from "./interfaces/IUNI.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {VestingLib} from "./libraries/VestingLib.sol";

/// TODO: Add Ownable.
contract UniVesting {
  using VestingLib for *;

  /// Thrown when the minting timestamp has not been updated, but a vesting window is being started.
  error MintingWindowClosed();

  /// Thrown if trying to intiate a vesting window with no balance.
  error NothingToVest();

  /// Thrown if the vesting window is not complete.
  error ActiveVestingWindow();

  /// The UNI token contract.
  IUNI public immutable UNI;

  /// The duration of each period, ie. 30 days.
  uint256 public immutable periodDuration;

  /// The total vesting period, ie. 365 days.
  uint256 public immutable totalVestingPeriod;

  /// The total number of periods in the vesting window, ie 12.
  uint256 public immutable totalPeriods;

  /// The checkpoint of the minting allowed after timestamp set on the UNI token contract. Stored to
  /// keep track of minting windows.
  /// Vesting should not be allowed to start if the minting window has not changed.
  uint256 public mintingAllowedAfterCheckpoint;

  /// The amount of tokens that are being vested in this window.
  uint256 public amountVesting;

  /// The start time of the vesting window.
  uint256 public startTime;

  /// If positive, it's the amount of tokens that have been claimed in this vesting window. It will
  /// be negative if there are tokens leftover from previous vesting windows, and a NEW vesting
  /// window has begun.
  int256 public claimed;

  constructor(address _uni, uint256 _periodDuration) {
    UNI = IUNI(_uni);
    periodDuration = _periodDuration;
    totalVestingPeriod = UNI.minimumTimeBetweenMints();
    totalPeriods = totalVestingPeriod / _periodDuration;
    mintingAllowedAfterCheckpoint = UNI.mintingAllowedAfter();
  }

  function start() public {
    require(UNI.mintingAllowedAfter() > mintingAllowedAfterCheckpoint, MintingWindowClosed());
    require(totalVested() == amountVesting, ActiveVestingWindow());

    /// Calculate the amount to vest.
    uint256 balance = UNI.balanceOf(address(this));
    uint256 leftover = amountVesting.sub(claimed);
    amountVesting = balance - leftover;
    require(amountVesting > 0, NothingToVest());

    /// Allow the leftover tokens to be claimed.
    claimed = -SafeCast.toInt256(leftover);

    /// Reset the vesting schedule.
    startTime = block.timestamp;
    mintingAllowedAfterCheckpoint = UNI.mintingAllowedAfter();
  }

  /// TODO: This should be callable with a recipient and only callable by the owner.
  /// Claim any already vested tokens, updating the claimed amount. It's possible that this sets the
  /// claimed amount to zero, if the only claimable tokens are leftover from a previous vest.
  function claim() public {
    uint256 _claimable = claimable();
    claimed = claimed.add(_claimable);
    UNI.transfer(msg.sender, _claimable);
  }

  /// The total amount of tokens that are claimable. This COULD return a value greater than
  /// amountVesting if multiple vesting windows have been started and have leftover tokens.
  function claimable() public view returns (uint256) {
    return totalVested().sub(claimed);
  }

  /// The totalVested amount in this vesting window. Bounded by 0 and amountVesting.
  function totalVested() public view returns (uint256) {
    if (block.timestamp < startTime) return 0;
    if (block.timestamp >= startTime + totalVestingPeriod) return amountVesting;

    uint256 elapsed = block.timestamp - startTime;

    return (elapsed / periodDuration) * amountVesting / totalPeriods;
  }
}
