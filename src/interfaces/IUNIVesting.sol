// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IUNI} from "./IUNI.sol";

/// @title IUNIVesting
/// @notice Interface for the UNIVesting contract
interface IUNIVesting {
  /// @notice Thrown when the minting timestamp has not been updated, but a vesting window is being
  /// started.
  error MintingWindowClosed();

  /// @notice Thrown if trying to intiate a vesting window with an insufficient balance.
  error NothingToVest();

  /// @notice Thrown if the vesting window is not complete.
  error ActiveVestingWindow();

  /// @notice The UNI token contract.
  function UNI() external view returns (IUNI);

  /// @notice The duration of each period, ie. 30 days.
  function periodDuration() external view returns (uint256);

  /// @notice The total vesting period, ie. 365 days.
  function totalVestingPeriod() external view returns (uint256);

  /// @notice The total number of periods in the vesting window, ie 12.
  function totalPeriods() external view returns (uint256);

  /// @notice The checkpoint of the minting allowed after timestamp set on the UNI token contract.
  /// Stored to keep track of minting windows.
  /// @dev Vesting should not be allowed to start if the minting window has not changed.
  function mintingAllowedAfterCheckpoint() external view returns (uint256);

  /// @notice The amount of tokens that are being vested in this window.
  function amountVesting() external view returns (uint256);

  /// @notice The start time of the vesting window.
  function startTime() external view returns (uint256);

  /// @notice If positive, it's the amount of tokens that have been claimed in this vesting window.
  /// It will be negative if there are tokens leftover from previous vesting windows, and a NEW
  /// vesting window has begun.
  function claimed() external view returns (int256);

  /// @notice The minimum amount of UNI required to be held by the contract to start a vesting
  /// window
  /// @dev This is to prevent DOS'ing and bricking the vesting contract with tiny amounts of UNI
  function MINIMUM_UNI_TO_VEST() external view returns (uint256);

  /// @notice Starts the vesting window.
  /// @dev The vesting window can only be started if the minting window has updated on the UNI token
  /// contract, and if there is not currently an active vest.
  function start() external;

  /// @notice Claims the vested tokens for a recipient.
  /// @param recipient The address to claim the tokens to.
  /// @dev Only callable by the owner.
  /// @dev It's possible that this sets the
  /// claimed amount to zero, if the only claimable tokens are leftover from a previous vest.
  function claim(address recipient) external;

  /// @notice The total amount of tokens that are claimable.
  /// @dev This COULD return a value greater than `amountVesting` if multiple vesting windows have
  /// been started and have leftover tokens.
  function claimable() external view returns (uint256);

  /// @notice The total amount of tokens that have been vested in this window.
  /// @dev Bounded by 0 and `amountVesting`.
  function totalVested() external view returns (uint256);
}
