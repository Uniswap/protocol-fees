// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

/// @title UNI Vesting Interface
/// @notice A vesting contract that releases UNI tokens quarterly to a designated recipient
interface IUNIVesting {
  /// @notice Thrown when an unauthorized caller tries to update the recipient address.
  error NotAuthorized();

  /// @notice Thrown when trying to transfer UNI more frequently than once a quarter.
  error OnlyQuarterly();

  /// @notice Thrown when trying to withdraw but the owner has not approved enough UNI tokens.
  error InsufficientAllowance();

  /// @notice Thrown when trying to update the vesting amount while tokens are available to
  /// withdraw.
  error CannotUpdateAmount();

  /// @notice Thrown when trying to update a setting to the current value.
  error NoChangeUpdate();

  /// @notice Emitted when the quarterly vesting amount is updated by the owner
  /// @param amount The new quarterly vesting amount
  event VestingAmountUpdated(uint256 amount);

  /// @notice Emitted when the recipient address is changed
  /// @param recipient The new recipient address
  event RecipientUpdated(address recipient);

  /// @notice Emitted when vested UNI tokens are withdrawn
  /// @param recipient The address that received the tokens
  /// @param amount The amount of tokens withdrawn
  /// @param quartersPaid The number of quarters paid out in this withdrawal
  event Withdrawn(address indexed recipient, uint256 amount, uint48 quartersPaid);

  /// @notice The UNI token contract
  /// @return ERC20 token being vested
  function UNI() external view returns (ERC20);

  /// @notice The maximum amount able to be transferred at each vesting period.
  /// @return uint256 quarterly vesting amount in wei
  function quarterlyVestingAmount() external view returns (uint256);

  /// @notice The recipient of the vested UNI.
  /// @return address of the recipient
  function recipient() external view returns (address);

  /// @notice The timestamp of the last settled quarterly boundary
  /// @return uint48 timestamp of the last settled quarterly boundary
  function lastUnlockTimestamp() external view returns (uint48);

  /// @notice Updates the quarterly vesting amount
  /// @param amount The new quarterly vesting amount in wei
  function updateVestingAmount(uint256 amount) external;

  /// @notice Updates the recipient address for vested tokens
  /// @param _recipient The new recipient address
  function updateRecipient(address _recipient) external;

  /// @notice Withdraws vested UNI tokens for all quarters that have passed
  function withdraw() external;

  /// @notice Calculates the number of complete quarters that have passed since the last withdrawal
  /// @return numQuarters Number of complete quarters available for withdrawal
  function quartersPassed() external view returns (uint48 numQuarters);
}
