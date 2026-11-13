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
  /// @param _startThreshold The threshold at the start of the decay.
  /// @param _floorThreshold The threshold the decay ends at.
  /// @param _halfLife The number of seconds over which the threshold halves.
  constructor(
    address _releaser,
    uint256 _startThreshold,
    uint256 _floorThreshold,
    uint256 _halfLife
  ) {
    // Upper bounds keep `_decay` from overflowing.
    require(
      _releaser != address(0) && _floorThreshold != 0 && _startThreshold > _floorThreshold
        && _startThreshold <= type(uint128).max && _halfLife != 0 && _halfLife <= type(uint64).max,
      InvalidParameters()
    );
    // Read governance from the token jar so it cannot be misconfigured.
    address governance = IOwned(address(IReleaser(_releaser).TOKEN_JAR())).owner();
    require(governance != address(0), InvalidParameters());
    RELEASER = IReleaser(_releaser);
    GOVERNANCE = governance;
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
    emit Started(block.timestamp, START_THRESHOLD);
    _setThreshold(START_THRESHOLD);
  }

  /// @inheritdoc IDecayingThresholdSetter
  function poke() external whileInControl returns (uint256 threshold) {
    require(startTime != 0, NotStarted());
    threshold = currentThreshold();
    _setThreshold(threshold);
    if (threshold == FLOOR_THRESHOLD) _returnControl();
  }

  function _setThreshold(uint256 threshold) internal {
    RELEASER.setThreshold(threshold);
    emit ThresholdUpdated(threshold);
  }

  function _returnControl() internal {
    controlReturned = true;
    RELEASER.setThresholdSetter(GOVERNANCE);
    IOwned(address(RELEASER)).transferOwnership(GOVERNANCE);
    emit ControlReturned();
  }

  /// @return threshold `START_THRESHOLD * 2^(-elapsed / HALF_LIFE)`, floored at `FLOOR_THRESHOLD`.
  /// @dev Interpolates linearly within each half-life, overstating the exact curve by at most 6.2%.
  function _decay(uint256 elapsed) internal view returns (uint256 threshold) {
    threshold = START_THRESHOLD >> (elapsed / HALF_LIFE);
    threshold -= threshold * (elapsed % HALF_LIFE) / (2 * HALF_LIFE);
    if (threshold < FLOOR_THRESHOLD) threshold = FLOOR_THRESHOLD;
  }
}
