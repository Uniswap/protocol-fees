// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IResourceManager} from "./base/IResourceManager.sol";

/// @title Decaying Threshold Setter Interface
/// @notice Temporarily owns a releaser and lowers its `threshold` along an exponential decay curve
/// until it reaches a floor, then hands ownership and the threshold setter role back to governance
interface IDecayingThresholdSetter {
  /// @notice Thrown when a caller other than `GOVERNANCE` calls a governance-only function
  error Unauthorized();

  /// @notice Thrown when the constructor parameters do not describe a valid decay
  error InvalidParameters();

  /// @notice Thrown when `start` is called more than once
  error AlreadyStarted();

  /// @notice Thrown when `poke` or `finalize` is called before `start`
  error NotStarted();

  /// @notice Thrown when `finalize` is called before the threshold has decayed to the floor
  error DecayNotComplete();

  /// @notice Thrown by `start`, `poke`, `finalize` and `reclaim` once ownership and the threshold
  /// setter role have been returned to `GOVERNANCE`, since this contract can no longer act
  error ControlAlreadyReturned();

  /// @notice Emitted when the decay starts
  event Started(uint256 startTime, uint256 startThreshold);

  /// @notice Emitted whenever this contract writes a new threshold to the releaser
  event ThresholdUpdated(uint256 threshold);

  /// @notice Emitted when ownership and the threshold setter role are returned to `GOVERNANCE`
  /// @param completed true when returned because the decay reached the floor (via `poke` or
  /// `finalize`), false when reclaimed early by governance
  event ControlReturned(bool completed);

  /// @return The releaser whose threshold this contract decays
  function RELEASER() external view returns (IResourceManager);

  /// @return The address that receives ownership and the threshold setter role back
  function GOVERNANCE() external view returns (address);

  /// @return The threshold written to the releaser when the decay starts
  function START_THRESHOLD() external view returns (uint256);

  /// @return The threshold the decay ends at
  function FLOOR_THRESHOLD() external view returns (uint256);

  /// @return The number of seconds over which the threshold halves
  function HALF_LIFE() external view returns (uint256);

  /// @return The timestamp at which the decay started, or 0 if it has not started
  function startTime() external view returns (uint256);

  /// @return True once ownership and the threshold setter role have been returned to `GOVERNANCE`
  function controlReturned() external view returns (bool);

  /// @notice The threshold implied by the decay curve at the current block timestamp
  /// @dev Returns `START_THRESHOLD` before `start` and never returns less than `FLOOR_THRESHOLD`
  function currentThreshold() external view returns (uint256);

  /// @notice Makes this contract the releaser's threshold setter, writes `START_THRESHOLD` and
  /// starts the decay clock
  /// @dev only callable by `GOVERNANCE`, once, after `GOVERNANCE` has transferred ownership of
  /// the releaser to this contract
  function start() external;

  /// @notice Writes `currentThreshold()` to the releaser. When that is `FLOOR_THRESHOLD` it also
  /// returns the threshold setter role and ownership of the releaser to `GOVERNANCE`, exactly as
  /// `finalize` does
  /// @dev Permissionless. Searchers are expected to call this in the same transaction as
  /// `release`, since the releaser charges whatever threshold was last written. The floor is
  /// written before control is returned, so a `release` later in the same transaction is charged
  /// the floor. Reverts with `ControlAlreadyReturned` once control is returned; searchers should
  /// then call `release` directly
  /// @return threshold The threshold written to the releaser
  function poke() external returns (uint256 threshold);

  /// @notice Writes `FLOOR_THRESHOLD` and returns the threshold setter role and ownership of the
  /// releaser to `GOVERNANCE`
  /// @dev Permissionless, once `currentThreshold()` has reached `FLOOR_THRESHOLD`. Equivalent to
  /// the first `poke` at the floor, for callers that only want the hand-back
  function finalize() external;

  /// @notice Returns the threshold setter role and ownership of the releaser to `GOVERNANCE`
  /// without changing the threshold
  /// @dev only callable by `GOVERNANCE`, at any time until control has been returned
  function reclaim() external;
}
