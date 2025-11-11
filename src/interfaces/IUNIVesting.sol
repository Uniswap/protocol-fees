// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

/// @title UNI Vesting Interface
/// @notice A vesting contract that releases UNI tokens quarterly to a designated recipient
/// @dev The contract starts vesting on January 1, 2026 and allows withdrawals every quarter
/// (approximately 90 days) The owner must approve the contract to spend UNI tokens on their
/// behalf
interface IUNIVesting {
  /// @notice Thrown when an unauthorized caller tries to update the recipient address.
  error NotAuthorized();

  /// @notice Thrown when trying to transfer UNI more frequently than once a quarter.
  error OnlyQuarterly();

  /// @notice Thrown when trying to update the vesting amount while tokens are available to
  /// withdraw.
  error CannotUpdateAmount();

  /// @notice Emitted when the quarterly vesting amount is updated by the owner
  /// @param amount The new quarterly vesting amount
  event VestingAmountUpdated(uint256 amount);

  /// @notice Emitted when the recipient address is changed
  /// @param recipient The new recipient address
  event RecipientUpdated(address recipient);

  /// @notice The start time for vesting
  /// @dev equivalent to January 1, 2026 00:00:00 UTC
  /// @return uint256 start time as a Unix timestamp
  function START_TIME() external view returns (uint256);

  /// @notice The seconds elapsed in one quarter
  /// @dev 7,776,000 seconds = 90 days
  /// @return uint256 number of seconds in one quarter
  function QUARTERLY_SECONDS() external view returns (uint256);

  /// @notice The UNI token contract
  /// @return ERC20 token being vested
  function UNI() external view returns (ERC20);

  /// @notice The maximum amount able to be transferred at each vesting period.
  /// @return uint256 quarterly vesting amount in wei
  function QUARTERLY_VESTING_AMOUNT() external view returns (uint256);

  /// @notice The recipient of the vested UNI.
  /// @return address of the recipient
  function recipient() external view returns (address);

  /// @notice The last time the UNI was transferred, set to the closest quarter that has not fully
  /// vested.
  /// @return uint256 timestamp of the last withdrawal
  function lastQuarterlyTimestamp() external view returns (uint256);

  /// @notice Updates the quarterly vesting amount
  /// @param amount The new quarterly vesting amount in wei
  /// @dev Can only be called by the owner and only when no active quarters are available to
  /// withdraw (i.e., quarters() == 0). This prevents changing the amount when tokens have already
  /// vested and are waiting to be claimed
  function updateVestingAmount(uint256 amount) external;

  /// @notice Updates the recipient address for vested tokens
  /// @param _recipient The new recipient address
  /// @dev Can be called by either the current owner or the current recipient
  function updateRecipient(address _recipient) external;

  /// @notice Withdraws all vested tokens that are available for the current period
  /// @dev Transfers UNI tokens from the owner to the recipient using transferFrom
  ///      The owner must have approved this contract to spend sufficient UNI tokens
  ///      Can only be called once per quarter (enforced by onlyQuarterly modifier)
  ///      Multiple quarters of vesting can be withdrawn in a single call if more than one quarter
  /// has passed
  function withdraw() external;

  /// @notice Calculates how many quarters have passed since the last withdrawal
  /// @dev Uses integer division, so partial quarters are not counted
  /// @return uint256 number of complete quarters that have elapsed since lastQuarterlyTimestamp
  function quarters() external view returns (uint256);
}
