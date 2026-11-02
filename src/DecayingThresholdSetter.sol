// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IResourceManager} from "./interfaces/base/IResourceManager.sol";
import {IOwned} from "./interfaces/base/IOwned.sol";
import {IDecayingThresholdSetter} from "./interfaces/IDecayingThresholdSetter.sol";

/// @title DecayingThresholdSetter
/// @notice Runs a descending-price auction on a releaser's `threshold`: it starts at
/// `START_THRESHOLD`, halves every `HALF_LIFE` seconds and stops at `FLOOR_THRESHOLD`. A searcher
/// releases once the threshold falls to the value they can extract, so the surplus that a fixed
/// threshold would leak to the first searcher is competed away and paid in `RESOURCE` instead.
/// @dev Lifecycle, driven by `GOVERNANCE` (the releaser's owner and threshold setter):
/// 1. Deploy, then in one governance action call `releaser.transferOwnership(this)` followed by
///    `this.start()`. Only the owner can change `thresholdSetter`, so this contract needs ownership
///    to be able to hand the role back later.
/// 2. Anyone calls `poke()` to write the current threshold; searchers bundle it with `release`.
///    The stored threshold only ever lags above the curve, never below it.
/// 3. Once the curve reaches the floor anyone calls `finalize()`, which writes the floor and
/// returns the threshold setter role and ownership to `GOVERNANCE`. `GOVERNANCE` can `reclaim()`
/// both at
///    any time instead.
/// The releaser's only owner-gated functions are `setThresholdSetter` and `transferOwnership`, so
/// governance gives up nothing else while this contract holds ownership.
/// @custom:security-contact security@uniswap.org
contract DecayingThresholdSetter is IDecayingThresholdSetter {
  /// @inheritdoc IDecayingThresholdSetter
  IResourceManager public immutable RELEASER;

  /// @inheritdoc IDecayingThresholdSetter
  address public immutable GOVERNANCE;

  /// @inheritdoc IDecayingThresholdSetter
  uint256 public immutable START_THRESHOLD;

  /// @inheritdoc IDecayingThresholdSetter
  uint256 public immutable FLOOR_THRESHOLD;

  /// @inheritdoc IDecayingThresholdSetter
  uint256 public immutable HALF_LIFE;

  /// @inheritdoc IDecayingThresholdSetter
  uint256 public startTime;

  modifier onlyGovernance() {
    require(msg.sender == GOVERNANCE, Unauthorized());
    _;
  }

  /// @param _releaser The releaser whose threshold is decayed
  /// @param _governance The releaser's current owner, which receives ownership and the threshold
  /// setter role back
  /// @param _startThreshold The threshold at the start of the decay
  /// @param _floorThreshold The threshold the decay ends at
  /// @param _halfLife The number of seconds over which the threshold halves
  constructor(
    address _releaser,
    address _governance,
    uint256 _startThreshold,
    uint256 _floorThreshold,
    uint256 _halfLife
  ) {
    // The bounds on the start threshold and half-life keep `_decay` free of overflow
    require(
      _releaser != address(0) && _governance != address(0) && _startThreshold > _floorThreshold
        && _startThreshold <= type(uint128).max && _halfLife != 0 && _halfLife <= type(uint64).max,
      InvalidParameters()
    );
    RELEASER = IResourceManager(_releaser);
    GOVERNANCE = _governance;
    START_THRESHOLD = _startThreshold;
    FLOOR_THRESHOLD = _floorThreshold;
    HALF_LIFE = _halfLife;
  }

  /// @inheritdoc IDecayingThresholdSetter
  function currentThreshold() public view returns (uint256) {
    if (startTime == 0) return START_THRESHOLD;
    return _decay(block.timestamp - startTime);
  }

  /// @inheritdoc IDecayingThresholdSetter
  function start() external onlyGovernance {
    require(startTime == 0, AlreadyStarted());
    startTime = block.timestamp;
    RELEASER.setThresholdSetter(address(this));
    RELEASER.setThreshold(START_THRESHOLD);
    emit Started(block.timestamp, START_THRESHOLD);
    emit ThresholdUpdated(START_THRESHOLD);
  }

  /// @inheritdoc IDecayingThresholdSetter
  function poke() external returns (uint256 threshold) {
    require(startTime != 0, NotStarted());
    threshold = currentThreshold();
    RELEASER.setThreshold(threshold);
    emit ThresholdUpdated(threshold);
  }

  /// @inheritdoc IDecayingThresholdSetter
  function finalize() external {
    require(startTime != 0, NotStarted());
    require(currentThreshold() == FLOOR_THRESHOLD, DecayNotComplete());
    RELEASER.setThreshold(FLOOR_THRESHOLD);
    emit ThresholdUpdated(FLOOR_THRESHOLD);
    _returnControl();
    emit ControlReturned(true);
  }

  /// @inheritdoc IDecayingThresholdSetter
  function reclaim() external onlyGovernance {
    _returnControl();
    emit ControlReturned(false);
  }

  function _returnControl() internal {
    RELEASER.setThresholdSetter(GOVERNANCE);
    IOwned(address(RELEASER)).transferOwnership(GOVERNANCE);
  }

  /// @dev `START_THRESHOLD * 2^(-elapsed / HALF_LIFE)`, floored at `FLOOR_THRESHOLD`. Whole
  /// half-lives are applied exactly with a right shift; within a half-life the value is linearly
  /// interpolated between the two neighbouring powers of two, which overstates the exact curve by
  /// at most ~6.2% and keeps it continuous and non-increasing.
  function _decay(uint256 elapsed) internal view returns (uint256 threshold) {
    threshold = START_THRESHOLD >> (elapsed / HALF_LIFE);
    threshold -= threshold * (elapsed % HALF_LIFE) / (2 * HALF_LIFE);
    if (threshold < FLOOR_THRESHOLD) threshold = FLOOR_THRESHOLD;
  }
}
