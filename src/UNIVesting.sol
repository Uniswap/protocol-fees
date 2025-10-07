// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IUNI} from "./interfaces/IUNI.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {VestingLib} from "./libraries/VestingLib.sol";
import {IUNIVesting} from "./interfaces/IUNIVesting.sol";

/// @title UNIVesting
/// @notice A contract for vesting UNI tokens over configurable time periods
/// @dev This contract allows for the vesting of UNI tokens with periodic claiming
/// functionality. It integrates with the UNI token's minting schedule to coordinate
/// vesting windows with minting cycles.
/// @custom:security-contact security@uniswap.org
contract UNIVesting is IUNIVesting, Owned {
  using VestingLib for *;

  /// @inheritdoc IUNIVesting
  IUNI public immutable UNI;

  /// @inheritdoc IUNIVesting
  uint256 public immutable periodDuration;

  /// @inheritdoc IUNIVesting
  uint256 public immutable totalVestingPeriod;

  /// @inheritdoc IUNIVesting
  uint256 public immutable totalPeriods;

  /// @inheritdoc IUNIVesting
  uint256 public mintingAllowedAfterCheckpoint;

  /// @inheritdoc IUNIVesting
  uint256 public amountVesting;

  /// @inheritdoc IUNIVesting
  uint256 public startTime;

  /// @inheritdoc IUNIVesting
  int256 public claimed;

  /// @inheritdoc IUNIVesting
  uint256 public constant MINIMUM_UNI_TO_VEST = 1000e18;

  /// @notice Constructs a new UNIVesting contract
  /// @param _uni The address of the UNI token contract
  /// @param _periodDuration The duration of each vesting period in seconds (e.g., 30 days)
  constructor(address _uni, uint256 _periodDuration) Owned(msg.sender) {
    UNI = IUNI(_uni);
    periodDuration = _periodDuration;
    totalVestingPeriod = UNI.minimumTimeBetweenMints();
    totalPeriods = totalVestingPeriod / _periodDuration;
    mintingAllowedAfterCheckpoint = UNI.mintingAllowedAfter();
  }

  /// @inheritdoc IUNIVesting
  function start() external {
    require(UNI.mintingAllowedAfter() > mintingAllowedAfterCheckpoint, MintingWindowClosed());
    require(totalVested() == amountVesting, ActiveVestingWindow());

    /// Calculate the amount to vest.
    uint256 balance = UNI.balanceOf(address(this));
    uint256 leftover = amountVesting.sub(claimed);
    amountVesting = balance - leftover;
    require(amountVesting >= MINIMUM_UNI_TO_VEST, NothingToVest());

    /// Allow the leftover tokens to be claimed.
    claimed = -SafeCast.toInt256(leftover);

    /// Reset the vesting schedule.
    startTime = block.timestamp;
    mintingAllowedAfterCheckpoint = UNI.mintingAllowedAfter();
  }

  /// @inheritdoc IUNIVesting
  function claim(address recipient) external onlyOwner {
    uint256 _claimable = claimable();
    claimed = claimed.add(_claimable);
    UNI.transfer(recipient, _claimable);
  }

  /// @inheritdoc IUNIVesting
  function claimable() public view returns (uint256) {
    return totalVested().sub(claimed);
  }

  /// @inheritdoc IUNIVesting
  function totalVested() public view returns (uint256) {
    if (block.timestamp < startTime) return 0;
    if (block.timestamp >= startTime + totalVestingPeriod) return amountVesting;

    uint256 elapsed = block.timestamp - startTime;

    return (elapsed / periodDuration) * amountVesting / totalPeriods;
  }
}
