// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IV4ProtocolFeeRuleset} from "./IV4FeePolicy.sol";

/// @dev One part of the piecewise-linear fee curve. For an LP fee, the protocol fee comes from the
/// bucket with the highest floor at or below the LP fee. If the LP fee is below all floors, the
/// fee comes from bucket 0. In each swap direction, the fee is
/// alpha + beta * (LP fee - floor) / 1_000_000, to a maximum of MAX_PROTOCOL_FEE.
struct FeeBucket {
  /// @dev The lowest LP fee of the bucket, in pips. Each floor is higher than the previous floor.
  uint24 lpFeeFloor;
  /// @dev The fee in each direction at the floor, in pips. The maximum is MAX_PROTOCOL_FEE (1000).
  uint24 alphaPips;
  /// @dev The slope: the fee in pips for each 1_000_000 pips of (LP fee - floor). The maximum is
  /// 1_000_000_000, which gives MAX_PROTOCOL_FEE for a delta of 1 pip.
  uint32 betaPips;
}

/// @title IV4StaticCurveRuleset
/// @notice A protocol fee ruleset that calculates the fee of a static-fee pool from its LP fee.
/// @dev The buckets are set at deployment and cannot change. To change the curve, deploy a new
/// ruleset and set it on the policy.
/// @custom:security-contact security@uniswap.org
interface IV4StaticCurveRuleset is IV4ProtocolFeeRuleset {
  // --- Errors ---

  /// @notice The alpha of a bucket is more than MAX_PROTOCOL_FEE.
  error InvalidFeeValue();

  /// @notice The beta of a bucket is more than 1_000_000_000.
  error MultiplierTooLarge();

  /// @notice There are no buckets.
  error EmptyBuckets();

  /// @notice The floor of a bucket is not higher than the floor of the previous bucket.
  error BucketsNotAscending();

  /// @notice There are more than 16 buckets.
  error TooManyBuckets();

  /// @notice The pool has a dynamic LP fee.
  error DynamicFeeNotSupported();

  // --- State ---

  /// @notice Returns the number of fee buckets.
  function feeBucketsLength() external view returns (uint256);

  /// @notice Returns the fee bucket at an index.
  /// @param index The index of the bucket. Bucket 0 has the lowest floor.
  /// @return lpFeeFloor The lowest LP fee of the bucket, in pips.
  /// @return alphaPips The fee in each direction at the floor, in pips.
  /// @return betaPips The slope of the bucket.
  function feeBucket(uint256 index)
    external
    view
    returns (uint24 lpFeeFloor, uint24 alphaPips, uint32 betaPips);

  /// @notice Calculates the protocol fee for an LP fee on this curve.
  /// @dev A ruleset for a hook looks up the hookless ruleset and calls this with the LP fee it
  /// uses, so a later change of that ruleset applies to the hook. The two swap directions have
  /// the same fee.
  /// @param lpFee The LP fee, in pips. This can be an effective LP fee above 1_000_000.
  /// @return The packed protocol fee.
  function getFeeForLpFee(uint24 lpFee) external view returns (uint24);
}
