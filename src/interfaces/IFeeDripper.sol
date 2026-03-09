// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";

/// @title IFeeDripper
interface IFeeDripper {
  /// @notice Emitted when a drip schedule is updated for a given currency.
  /// @param currency The currency address whose drip was updated
  /// @param fullyReleasedBlock The block number at which the current drip will be fully released
  /// @param perBlockRate The amount of tokens released per block
  event DripUpdated(
    address indexed currency, uint256 indexed fullyReleasedBlock, uint160 perBlockRate
  );
  /// @notice Emitted when a release to the token jar is completed.
  /// @param currency The currency address that was released
  /// @param amount The amount of tokens released
  event Released(address indexed currency, uint256 amount);
  /// @notice Emitted when the release settings are updated by the owner.
  /// @param releaseWindow The new release window in blocks
  /// @param windowResetBps The new window reset threshold in basis points
  event ReleaseSettingsSet(uint16 releaseWindow, uint16 windowResetBps);

  /// @notice Thrown when the owner address provided in the constructor is zero address.
  error InvalidOwner();
  /// @notice Thrown when the token jar address provided in the constructor is zero address.
  error InvalidTokenJar();
  /// @notice Thrown when the supplied release window is zero.
  error InvalidReleaseWindow();
  /// @notice Thrown when the supplied window reset basis points is greater than 10_000.
  error InvalidWindowResetBps();

  /// @notice Syncs deposits and updates the active drip schedule for `currency`.
  /// @dev Releases accrued amount first, then recomputes the stream from the remaining balance
  ///      (unreleased prior balance + any new deposits).
  ///      If a drip is active and `newDeposit / previousBalance < windowResetBps / 10_000`,
  ///      the schedule keeps the existing end block (no full reset). Otherwise it resets to a
  ///      fresh `releaseWindow`.
  ///      Callable by anyone.
  ///      Griefing note: an attacker can still delay flow by adding enough balance to meet the
  ///      reset threshold and repeatedly calling `drip()`, but cannot steal or redirect funds.
  /// @param currency The currency to drip
  function drip(Currency currency) external;

  /// @notice Releases accrued amount for `currency` to `TOKEN_JAR` without starting a new drip.
  /// @dev Only accrual from the current stream is released.
  ///      Does not recompute rate or end block, and does not incorporate newly deposited idle
  ///      balance into the stream (that requires `drip()`).
  ///      Callable by anyone.
  /// @param currency The currency to release
  function release(Currency currency) external;

  /// @notice Sets the release window.
  /// @dev Only callable by the owner.
  /// @param _releaseWindow The new release window
  /// @param _windowResetBps The new window reset basis points
  function setReleaseSettings(uint16 _releaseWindow, uint16 _windowResetBps) external;
}
