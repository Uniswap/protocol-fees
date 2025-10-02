// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IUNI} from "./interfaces/IUNI.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {VestingLib} from "./libraries/VestingLib.sol";
import {IUniVesting} from "./interfaces/IUniVesting.sol";

/// @title UniVesting
/// @notice A contract for vesting UNI tokens over configurable time periods
/// @dev This contract allows for the vesting of UNI tokens with periodic claiming
/// functionality. It integrates with the UNI token's minting schedule to coordinate
/// vesting windows with minting cycles.
/// @custom:security-contact security@uniswap.org
contract UniVesting is IUniVesting, Owned {
  using VestingLib for *;

  /// @inheritdoc IUniVesting
  IUNI public immutable UNI;

  /// @inheritdoc IUniVesting
  uint256 public immutable periodDuration;

  /// @inheritdoc IUniVesting
  uint256 public immutable totalVestingPeriod;

  /// @inheritdoc IUniVesting
  uint256 public immutable totalPeriods;

  /// @inheritdoc IUniVesting
  uint256 public mintingAllowedAfterCheckpoint;

  /// @inheritdoc IUniVesting
  uint256 public amountVesting;

  /// @inheritdoc IUniVesting
  uint256 public startTime;

  /// @inheritdoc IUniVesting
  int256 public claimed;

  /// @notice Constructs a new UniVesting contract
  /// @param _uni The address of the UNI token contract
  /// @param _periodDuration The duration of each vesting period in seconds (e.g., 30 days)
  constructor(address _uni, uint256 _periodDuration) Owned(msg.sender) {
    UNI = IUNI(_uni);
    periodDuration = _periodDuration;
    totalVestingPeriod = UNI.minimumTimeBetweenMints();
    totalPeriods = totalVestingPeriod / _periodDuration;
    mintingAllowedAfterCheckpoint = UNI.mintingAllowedAfter();
  }

  /// @inheritdoc IUniVesting
  function start() external {
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

  /// @inheritdoc IUniVesting
  function claim(address recipient) external onlyOwner {
    uint256 _claimable = claimable();
    claimed = claimed.add(_claimable);
    UNI.transfer(recipient, _claimable);
  }

  /// @inheritdoc IUniVesting
  function claimable() public view returns (uint256) {
    return totalVested().sub(claimed);
  }

  /// @inheritdoc IUniVesting
  function totalVested() public view returns (uint256) {
    if (block.timestamp < startTime) return 0;
    if (block.timestamp >= startTime + totalVestingPeriod) return amountVesting;

    uint256 elapsed = block.timestamp - startTime;

    return (elapsed / periodDuration) * amountVesting / totalPeriods;
  }
}
