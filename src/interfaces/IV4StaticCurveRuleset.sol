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
/// @custom:security-contact security@uniswap.org
interface IV4StaticCurveRuleset is IV4ProtocolFeeRuleset {
  // --- Errors ---

  /// @notice The caller is not the fee setter.
  error Unauthorized();

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

  // --- Events ---

  /// @notice The owner changes the fee setter.
  /// @param oldFeeSetter The previous fee setter.
  /// @param newFeeSetter The new fee setter.
  event FeeSetterUpdated(address indexed oldFeeSetter, address indexed newFeeSetter);

  /// @notice The fee setter replaces or removes the fee buckets.
  /// @param bucketCount The number of buckets after the change.
  event FeeBucketsUpdated(uint256 bucketCount);

  // --- State ---

  /// @notice The address that can change the fee buckets.
  function feeSetter() external view returns (address);

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
  /// @dev A hook looks up the hookless ruleset and calls this with the LP fee it uses, so a later
  /// change of that ruleset applies to the hook. The two swap directions have the same fee. With
  /// no buckets, the fee is 0.
  /// @param lpFee The LP fee, in pips. This can be an effective LP fee above 1_000_000.
  /// @return The packed protocol fee.
  function getFeeForLpFee(uint24 lpFee) external view returns (uint24);

  // --- Admin (onlyOwner) ---

  /// @notice Sets the fee setter. Only the owner can call this function.
  /// @param newFeeSetter The new fee setter.
  function setFeeSetter(address newFeeSetter) external;

  // --- Fee Buckets (onlyFeeSetter) ---

  /// @notice Replaces all fee buckets. Only the fee setter can call this function.
  /// @dev There must be 1 to 16 buckets, and each floor must be higher than the previous floor.
  /// A pool with an LP fee below the lowest floor pays the alpha of bucket 0.
  /// @param buckets The new buckets, from the lowest floor to the highest floor.
  function setFeeBuckets(FeeBucket[] calldata buckets) external;

  /// @notice Removes all fee buckets. After that, the fee of each static-fee pool is 0. Only the
  /// fee setter can call this function.
  function clearFeeBuckets() external;
}
