// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IReleaser} from "./IReleaser.sol";

/// @title Decaying Threshold Setter Interface
/// @notice Lowers a releaser's `threshold` along a halving curve to a floor, then returns control
/// of the releaser to governance.
/// @dev Control means ownership and the threshold setter role of the releaser. Once control is
/// returned, all non-view functions revert with `ControlAlreadyReturned`.
interface IDecayingThresholdSetter {
  /// @notice Thrown when the caller is not `GOVERNANCE`.
  error Unauthorized();

  /// @notice Thrown when the constructor parameters do not describe a valid decay.
  error InvalidParameters();

  /// @notice Thrown when `_governance` does not own the releaser's token jar.
  error GovernanceNotJarOwner();

  /// @notice Thrown when the token jar does not release through the releaser.
  error ReleaserNotActive();

  /// @notice Thrown when the decay has already started.
  error AlreadyStarted();

  /// @notice Thrown when the decay has not started.
  error NotStarted();

  /// @notice Thrown when the threshold has not decayed to the floor.
  error DecayNotComplete();

  /// @notice Thrown once control has been returned to `GOVERNANCE`.
  error ControlAlreadyReturned();

  /// @notice Emitted when the decay starts.
  event Started(uint256 startTime, uint256 startThreshold);

  /// @notice Emitted when a threshold is written to the releaser.
  event ThresholdUpdated(uint256 threshold);

  /// @notice Emitted when control is returned to `GOVERNANCE`.
  /// @param completed True when the decay reached the floor, false when `GOVERNANCE` reclaimed
  /// control early.
  event ControlReturned(bool completed);

  /// @return The releaser whose threshold decays.
  function RELEASER() external view returns (IReleaser);

  /// @return The address control is returned to.
  function GOVERNANCE() external view returns (address);

  /// @return The threshold when the decay starts.
  function START_THRESHOLD() external view returns (uint256);

  /// @return The threshold the decay ends at.
  function FLOOR_THRESHOLD() external view returns (uint256);

  /// @return The number of seconds over which the threshold halves.
  function HALF_LIFE() external view returns (uint256);

  /// @return The timestamp the decay started at, or 0 before `start`.
  function startTime() external view returns (uint256);

  /// @return True once control has been returned to `GOVERNANCE`.
  function controlReturned() external view returns (bool);

  /// @return The threshold on the decay curve at the current timestamp, or `START_THRESHOLD`
  /// before `start`.
  function currentThreshold() external view returns (uint256);

  /// @notice Writes `START_THRESHOLD` to the releaser and starts the decay.
  /// @dev Only callable by `GOVERNANCE`. Reverts unless this contract owns the releaser and the
  /// token jar releases through it.
  function start() external;

  /// @notice Writes the current threshold to the releaser, and returns control once it reaches
  /// the floor.
  /// @dev Permissionless. Searchers call it in the same transaction as `IReleaser.release`, which
  /// charges the last written threshold.
  /// @return threshold The threshold written.
  function poke() external returns (uint256 threshold);

  /// @notice Writes `FLOOR_THRESHOLD` to the releaser and returns control.
  /// @dev Permissionless once the threshold has decayed to the floor.
  function finalize() external;

  /// @notice Returns control to `GOVERNANCE` without changing the threshold.
  /// @dev Only callable by `GOVERNANCE`.
  function reclaim() external;
}
