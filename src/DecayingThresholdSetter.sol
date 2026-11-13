// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IOwned} from "./interfaces/base/IOwned.sol";
import {IReleaser} from "./interfaces/IReleaser.sol";
import {IDecayingThresholdSetter} from "./interfaces/IDecayingThresholdSetter.sol";

/// @title DecayingThresholdSetter
/// @notice Runs a descending-price auction on a releaser's `threshold`, so searchers compete away
/// the surplus that a fixed threshold would leak. Once the decay ends, the releaser is left with a
/// threshold of `_floorThreshold`, and ownership and threshold setting powers are set to
/// governance.
/// @dev Assumes the releaser's only owner-gated functions are
/// `ResourceManager.setThresholdSetter` and `IOwned.transferOwnership`.
/// @custom:security-contact security@uniswap.org
contract DecayingThresholdSetter is IDecayingThresholdSetter {
  /// @inheritdoc IDecayingThresholdSetter
  IReleaser public immutable RELEASER;

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

  /// @inheritdoc IDecayingThresholdSetter
  bool public controlReturned;

  modifier onlyGovernance() {
    require(msg.sender == GOVERNANCE, Unauthorized());
    _;
  }

  modifier whileInControl() {
    require(!controlReturned, ControlAlreadyReturned());
    _;
  }

  /// @param _releaser The releaser whose threshold decays.
  /// @param _governance The address of governance on the current chain.
  /// @param _startThreshold The threshold at the start of the decay.
  /// @param _floorThreshold The threshold the decay ends at.
  /// @param _halfLife The number of seconds over which the threshold halves.
  constructor(
    address _releaser,
    address _governance,
    uint256 _startThreshold,
    uint256 _floorThreshold,
    uint256 _halfLife
  ) {
    // Upper bounds keep `_decay` from overflowing.
    require(
      _releaser != address(0) && _governance != address(0) && _startThreshold > _floorThreshold
        && _startThreshold <= type(uint128).max && _halfLife != 0 && _halfLife <= type(uint64).max,
      InvalidParameters()
    );
    // Check the governance address against the token jar's owner for safety.
    require(
      IOwned(address(IReleaser(_releaser).TOKEN_JAR())).owner() == _governance,
      GovernanceNotJarOwner()
    );
    RELEASER = IReleaser(_releaser);
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
  function start() external onlyGovernance whileInControl {
    require(startTime == 0, AlreadyStarted());
    // Searchers must be able to release while the threshold decays.
    require(RELEASER.TOKEN_JAR().releaser() == address(RELEASER), ReleaserNotActive());
    startTime = block.timestamp;
    RELEASER.setThresholdSetter(address(this));
    RELEASER.setThreshold(START_THRESHOLD);
    emit Started(block.timestamp, START_THRESHOLD);
    emit ThresholdUpdated(START_THRESHOLD);
  }

  /// @inheritdoc IDecayingThresholdSetter
  function poke() external whileInControl returns (uint256 threshold) {
    require(startTime != 0, NotStarted());
    threshold = currentThreshold();
    if (threshold == FLOOR_THRESHOLD) {
      _finalize();
    } else {
      RELEASER.setThreshold(threshold);
      emit ThresholdUpdated(threshold);
    }
  }

  /// @inheritdoc IDecayingThresholdSetter
  function finalize() external whileInControl {
    require(startTime != 0, NotStarted());
    require(currentThreshold() == FLOOR_THRESHOLD, DecayNotComplete());
    _finalize();
  }

  /// @inheritdoc IDecayingThresholdSetter
  function reclaim() external onlyGovernance whileInControl {
    _returnControl();
    emit ControlReturned(false);
  }

  /// @dev Assumes the threshold has decayed to the floor.
  function _finalize() internal {
    RELEASER.setThreshold(FLOOR_THRESHOLD);
    emit ThresholdUpdated(FLOOR_THRESHOLD);
    _returnControl();
    emit ControlReturned(true);
  }

  function _returnControl() internal {
    controlReturned = true;
    RELEASER.setThresholdSetter(GOVERNANCE);
    IOwned(address(RELEASER)).transferOwnership(GOVERNANCE);
  }

  /// @return threshold `START_THRESHOLD * 2^(-elapsed / HALF_LIFE)`, floored at `FLOOR_THRESHOLD`.
  /// @dev Interpolates linearly within each half-life, overstating the exact curve by at most 6.2%.
  function _decay(uint256 elapsed) internal view returns (uint256 threshold) {
    threshold = START_THRESHOLD >> (elapsed / HALF_LIFE);
    threshold -= threshold * (elapsed % HALF_LIFE) / (2 * HALF_LIFE);
    if (threshold < FLOOR_THRESHOLD) threshold = FLOOR_THRESHOLD;
  }
}
