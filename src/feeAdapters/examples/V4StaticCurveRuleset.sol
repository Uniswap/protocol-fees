// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "solmate/src/auth/Owned.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {IV4ProtocolFeeRuleset} from "../../interfaces/IV4FeePolicy.sol";
import {IV4StaticCurveRuleset, FeeBucket} from "../../interfaces/IV4StaticCurveRuleset.sol";

/// @title V4StaticCurveRuleset
/// @notice An example protocol fee ruleset for V4FeePolicy. It calculates the fee of a static-fee
/// pool from its LP fee with a piecewise-linear curve of fee buckets.
/// @custom:security-contact security@uniswap.org
contract V4StaticCurveRuleset is IV4StaticCurveRuleset, Owned {
  using LPFeeLibrary for uint24;

  /// @dev The denominator of `betaPips`. 1_000_000 is 100%, the same as the v4-core LP fee
  /// denominator.
  uint24 internal constant MULTIPLIER_DENOMINATOR = LPFeeLibrary.MAX_LP_FEE;

  /// @dev The maximum number of fee buckets. It keeps the loop in `_computeFee` short.
  uint256 internal constant MAX_BUCKETS = 16;

  /// @dev The maximum `betaPips`. At this slope, a delta of 1 pip gives MAX_PROTOCOL_FEE. A higher
  /// slope gives the same fees.
  uint32 internal constant MAX_BETA_PIPS =
    uint32(uint256(MULTIPLIER_DENOMINATOR) * ProtocolFeeLibrary.MAX_PROTOCOL_FEE);

  /// @inheritdoc IV4StaticCurveRuleset
  address public feeSetter;

  /// @dev The fee buckets, from the lowest floor to the highest floor. With no buckets, the fee of
  /// each static-fee pool is 0.
  FeeBucket[] internal _feeBuckets;

  /// @notice Reverts if the caller is not the fee setter.
  modifier onlyFeeSetter() {
    if (msg.sender != feeSetter) revert Unauthorized();
    _;
  }

  constructor(address owner, address _feeSetter) Owned(owner) {
    feeSetter = _feeSetter;
  }

  /// @inheritdoc IV4ProtocolFeeRuleset
  /// @dev Reverts for a dynamic-fee pool. The key of a dynamic-fee pool has the 0x800000 flag, not
  /// an LP fee.
  function getProtocolFee(PoolKey calldata key) external view returns (uint24) {
    if (key.fee.isDynamicFee()) revert DynamicFeeNotSupported();
    return _computeFee(key.fee);
  }

  /// @inheritdoc IV4StaticCurveRuleset
  function getFeeForLpFee(uint24 lpFee) external view returns (uint24) {
    return _computeFee(lpFee);
  }

  /// @inheritdoc IV4StaticCurveRuleset
  function feeBucketsLength() external view returns (uint256) {
    return _feeBuckets.length;
  }

  /// @inheritdoc IV4StaticCurveRuleset
  function feeBucket(uint256 index)
    external
    view
    returns (uint24 lpFeeFloor, uint24 alphaPips, uint32 betaPips)
  {
    FeeBucket storage b = _feeBuckets[index];
    return (b.lpFeeFloor, b.alphaPips, b.betaPips);
  }

  /// @inheritdoc IV4StaticCurveRuleset
  function setFeeSetter(address newFeeSetter) external onlyOwner {
    emit FeeSetterUpdated(feeSetter, newFeeSetter);
    feeSetter = newFeeSetter;
  }

  /// @inheritdoc IV4StaticCurveRuleset
  function setFeeBuckets(FeeBucket[] calldata buckets) external onlyFeeSetter {
    uint256 len = buckets.length;
    if (len == 0) revert EmptyBuckets();
    if (len > MAX_BUCKETS) revert TooManyBuckets();

    delete _feeBuckets;

    uint24 prevFloor;
    for (uint256 i; i < len; ++i) {
      FeeBucket calldata b = buckets[i];
      if (i > 0 && b.lpFeeFloor <= prevFloor) revert BucketsNotAscending();
      if (b.alphaPips > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) revert InvalidFeeValue();
      if (b.betaPips > MAX_BETA_PIPS) revert MultiplierTooLarge();
      _feeBuckets.push(b);
      prevFloor = b.lpFeeFloor;
    }

    emit FeeBucketsUpdated(len);
  }

  /// @inheritdoc IV4StaticCurveRuleset
  function clearFeeBuckets() external onlyFeeSetter {
    delete _feeBuckets;
    emit FeeBucketsUpdated(0);
  }

  /// @dev Calculates the fee from `_feeBuckets`. The fee is the same in the two swap directions.
  function _computeFee(uint24 lpFee) internal view returns (uint24) {
    uint256 len = _feeBuckets.length;
    if (len == 0) return 0;

    FeeBucket memory bucket = _feeBuckets[0];
    for (uint256 i = len; i > 1; --i) {
      FeeBucket memory candidate = _feeBuckets[i - 1];
      if (candidate.lpFeeFloor <= lpFee) {
        bucket = candidate;
        break;
      }
    }

    uint256 delta = lpFee >= bucket.lpFeeFloor ? lpFee - bucket.lpFeeFloor : 0;
    uint256 perDirection =
      uint256(bucket.alphaPips) + uint256(bucket.betaPips) * delta / MULTIPLIER_DENOMINATOR;
    if (perDirection > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) {
      perDirection = ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
    }
    return uint24((perDirection << 12) | perDirection);
  }
}
