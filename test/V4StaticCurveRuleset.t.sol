// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test, stdError} from "forge-std/Test.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";

import {V4StaticCurveRuleset} from "../src/feeAdapters/rulesets/V4StaticCurveRuleset.sol";
import {IV4StaticCurveRuleset, FeeBucket} from "../src/interfaces/IV4StaticCurveRuleset.sol";

/// @dev Each section starts with the branch tree of one function. The tests are in the same
/// sequence as the tree. The buckets are set at deployment, thus each test deploys its own curve.
contract V4StaticCurveRulesetTest is Test {
  /// @dev The maximum `betaPips` of a bucket. At this slope, a delta of 1 pip gives
  /// MAX_PROTOCOL_FEE.
  uint32 internal constant MAX_BETA_PIPS = 1_000_000_000;

  /// @dev The denominator of `betaPips`. A slope of 1_000_000 adds 1 pip of fee for each pip of
  /// LP fee.
  uint256 internal constant BETA_DENOMINATOR = 1_000_000;

  /// @dev Makes `count` correct buckets from fuzzed values:
  /// - The first floor is 100_000 or less. Each next floor is 1 to 50_000 higher, thus all 16
  ///   floors are below MAX_LP_FEE.
  /// - Each alpha is MAX_PROTOCOL_FEE or less.
  /// - Each beta is MAX_BETA_PIPS or less.
  function _boundFeeBuckets(FeeBucket[16] memory raw, uint256 count)
    internal
    pure
    returns (FeeBucket[] memory buckets)
  {
    buckets = new FeeBucket[](count);
    uint24 lpFeeFloor = uint24(bound(raw[0].lpFeeFloor, 0, 100_000));
    for (uint256 i; i < count; ++i) {
      if (i > 0) lpFeeFloor += uint24(bound(raw[i].lpFeeFloor, 1, 50_000));
      buckets[i] = FeeBucket({
        lpFeeFloor: lpFeeFloor,
        alphaPips: uint24(bound(raw[i].alphaPips, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE)),
        betaPips: uint32(bound(raw[i].betaPips, 0, MAX_BETA_PIPS))
      });
    }
  }

  /// @dev The curve of proposal 6, in pips. Each beta is rounded up, because the fee is rounded
  /// down.
  function _proposal6Buckets() internal pure returns (FeeBucket[] memory buckets) {
    buckets = new FeeBucket[](8);
    buckets[0] = FeeBucket({lpFeeFloor: 0, alphaPips: 1, betaPips: 0});
    buckets[1] = FeeBucket({lpFeeFloor: 3, alphaPips: 1, betaPips: 263_889}); // 19/72
    buckets[2] = FeeBucket({lpFeeFloor: 75, alphaPips: 20, betaPips: 200_000});
    buckets[3] = FeeBucket({lpFeeFloor: 100, alphaPips: 25, betaPips: 272_728}); // 3/11
    buckets[4] = FeeBucket({lpFeeFloor: 375, alphaPips: 100, betaPips: 200_000});
    buckets[5] = FeeBucket({lpFeeFloor: 500, alphaPips: 125, betaPips: 137_500}); // 11/80
    buckets[6] = FeeBucket({lpFeeFloor: 2500, alphaPips: 400, betaPips: 200_000});
    buckets[7] = FeeBucket({lpFeeFloor: 5500, alphaPips: 1000, betaPips: 0});
  }

  // ============ constructor ============
  //
  // constructor
  // ├── when there are no buckets
  // │   └── it reverts with EmptyBuckets
  // ├── when there are more than 16 buckets
  // │   └── it reverts with TooManyBuckets
  // └── when there are 1 to 16 buckets
  //     ├── when a floor is not higher than the previous floor
  //     │   └── it reverts with BucketsNotAscending
  //     ├── when an alpha is more than MAX_PROTOCOL_FEE
  //     │   └── it reverts with InvalidFeeValue
  //     ├── when a beta is more than MAX_BETA_PIPS
  //     │   └── it reverts with MultiplierTooLarge
  //     └── when all buckets are correct
  //         └── it sets the fee buckets

  function test_constructor_RevertWhen_ThereAreNoBuckets() public {
    // When: there are no buckets.
    // Then: the constructor reverts with EmptyBuckets.
    vm.expectRevert(IV4StaticCurveRuleset.EmptyBuckets.selector);
    new V4StaticCurveRuleset(new FeeBucket[](0));
  }

  function testFuzz_constructor_RevertWhen_ThereAreMoreThan16Buckets(uint256 count) public {
    // When: there are more than 16 buckets with higher floors.
    count = bound(count, 17, 64);
    FeeBucket[] memory buckets = new FeeBucket[](count);
    for (uint256 i; i < count; ++i) {
      buckets[i].lpFeeFloor = uint24(i);
    }

    // Then: the constructor reverts with TooManyBuckets.
    vm.expectRevert(IV4StaticCurveRuleset.TooManyBuckets.selector);
    new V4StaticCurveRuleset(buckets);
  }

  function testFuzz_constructor_RevertWhen_AFloorIsNotHigherThanThePreviousFloor(
    FeeBucket[16] memory raw,
    uint256 count,
    uint256 index,
    uint24 lpFeeFloor
  ) public {
    // When: there are 2 to 16 buckets.
    count = bound(count, 2, 16);
    FeeBucket[] memory buckets = _boundFeeBuckets(raw, count);

    // When: the floor of one bucket is not higher than the previous floor.
    index = bound(index, 1, count - 1);
    buckets[index].lpFeeFloor = uint24(bound(lpFeeFloor, 0, buckets[index - 1].lpFeeFloor));

    // Then: the constructor reverts with BucketsNotAscending.
    vm.expectRevert(IV4StaticCurveRuleset.BucketsNotAscending.selector);
    new V4StaticCurveRuleset(buckets);
  }

  function testFuzz_constructor_RevertWhen_AnAlphaIsMoreThanMaxProtocolFee(
    FeeBucket[16] memory raw,
    uint256 count,
    uint256 index,
    uint24 alphaPips
  ) public {
    // When: there are 1 to 16 buckets.
    count = bound(count, 1, 16);
    FeeBucket[] memory buckets = _boundFeeBuckets(raw, count);

    // When: the alpha of one bucket is more than MAX_PROTOCOL_FEE.
    index = bound(index, 0, count - 1);
    buckets[index].alphaPips =
      uint24(bound(alphaPips, ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1, type(uint24).max));

    // Then: the constructor reverts with InvalidFeeValue.
    vm.expectRevert(IV4StaticCurveRuleset.InvalidFeeValue.selector);
    new V4StaticCurveRuleset(buckets);
  }

  function testFuzz_constructor_RevertWhen_ABetaIsMoreThanMaxBetaPips(
    FeeBucket[16] memory raw,
    uint256 count,
    uint256 index,
    uint32 betaPips
  ) public {
    // When: there are 1 to 16 buckets.
    count = bound(count, 1, 16);
    FeeBucket[] memory buckets = _boundFeeBuckets(raw, count);

    // When: the beta of one bucket is more than MAX_BETA_PIPS.
    index = bound(index, 0, count - 1);
    buckets[index].betaPips = uint32(bound(betaPips, MAX_BETA_PIPS + 1, type(uint32).max));

    // Then: the constructor reverts with MultiplierTooLarge.
    vm.expectRevert(IV4StaticCurveRuleset.MultiplierTooLarge.selector);
    new V4StaticCurveRuleset(buckets);
  }

  function testFuzz_constructor_WhenAllBucketsAreCorrect(FeeBucket[16] memory raw, uint256 count)
    public
  {
    // When: all of the 1 to 16 buckets are correct.
    FeeBucket[] memory buckets = _boundFeeBuckets(raw, bound(count, 1, 16));
    V4StaticCurveRuleset curve = new V4StaticCurveRuleset(buckets);

    // Then: the constructor sets the fee buckets.
    assertEq(curve.feeBucketsLength(), buckets.length);
    for (uint256 i; i < buckets.length; ++i) {
      (uint24 lpFeeFloor, uint24 alphaPips, uint32 betaPips) = curve.feeBucket(i);
      assertEq(lpFeeFloor, buckets[i].lpFeeFloor);
      assertEq(alphaPips, buckets[i].alphaPips);
      assertEq(betaPips, buckets[i].betaPips);
    }
  }

  // ============ getProtocolFee ============
  //
  // getProtocolFee
  // ├── when the pool has a dynamic LP fee
  // │   └── it reverts with DynamicFeeNotSupported
  // └── when the pool has a static LP fee
  //     ├── when the LP fee is below the floor of bucket 0
  //     │   └── it returns the alpha of bucket 0 in the two directions
  //     ├── when the LP fee is in bucket 0
  //     │   └── it calculates the fee from bucket 0
  //     ├── when the LP fee is in a higher bucket
  //     │   └── it calculates the fee from that bucket
  //     └── when the calculated fee is more than MAX_PROTOCOL_FEE
  //         └── it returns MAX_PROTOCOL_FEE in the two directions
  //
  // The LP fee is in bucket k when it is at or above the floor of bucket k and below the floor of
  // bucket k + 1. In each swap direction, the calculated fee is
  // alpha + beta * (LP fee - floor) / 1_000_000.

  function testFuzz_getProtocolFee_RevertWhen_ThePoolHasADynamicLPFee(
    PoolKey memory key,
    FeeBucket[16] memory raw,
    uint256 count
  ) public {
    // Given: fee buckets.
    V4StaticCurveRuleset curve =
      new V4StaticCurveRuleset(_boundFeeBuckets(raw, bound(count, 1, 16)));

    // When: the pool has a dynamic LP fee.
    key.fee = LPFeeLibrary.DYNAMIC_FEE_FLAG;

    // Then: getProtocolFee reverts with DynamicFeeNotSupported.
    vm.expectRevert(IV4StaticCurveRuleset.DynamicFeeNotSupported.selector);
    curve.getProtocolFee(key);
  }

  function testFuzz_getProtocolFee_WhenTheLPFeeIsBelowTheFloorOfBucket0(
    PoolKey memory key,
    FeeBucket[16] memory raw,
    uint256 count
  ) public {
    // Given: fee buckets, and the floor of bucket 0 is more than zero.
    raw[0].lpFeeFloor = uint24(bound(raw[0].lpFeeFloor, 1, 100_000));
    FeeBucket[] memory buckets = _boundFeeBuckets(raw, bound(count, 1, 16));
    V4StaticCurveRuleset curve = new V4StaticCurveRuleset(buckets);

    // When: the pool has a static LP fee below the floor of bucket 0.
    key.fee = uint24(bound(key.fee, 0, buckets[0].lpFeeFloor - 1));

    // Then: getProtocolFee returns the alpha of bucket 0 in the two directions.
    uint24 alpha = buckets[0].alphaPips;
    assertEq(curve.getProtocolFee(key), alpha << 12 | alpha);
  }

  function testFuzz_getProtocolFee_WhenTheLPFeeIsInBucket0(
    PoolKey memory key,
    FeeBucket[16] memory raw,
    uint256 count
  ) public {
    // Given: fee buckets.
    count = bound(count, 1, 16);
    FeeBucket[] memory buckets = _boundFeeBuckets(raw, count);

    // When: the pool has a static LP fee in bucket 0.
    uint256 ceiling = count > 1 ? buckets[1].lpFeeFloor - 1 : LPFeeLibrary.MAX_LP_FEE;
    key.fee = uint24(bound(key.fee, buckets[0].lpFeeFloor, ceiling));

    // Given: the slope of bucket 0 keeps the fee at or below MAX_PROTOCOL_FEE.
    FeeBucket memory lowest = buckets[0];
    uint256 delta = key.fee - lowest.lpFeeFloor;
    if (delta > 0) {
      uint256 maxBeta =
        (ProtocolFeeLibrary.MAX_PROTOCOL_FEE - lowest.alphaPips) * BETA_DENOMINATOR / delta;
      lowest.betaPips = uint32(bound(lowest.betaPips, 0, maxBeta));
    }
    V4StaticCurveRuleset curve = new V4StaticCurveRuleset(buckets);

    // Then: getProtocolFee calculates the fee from bucket 0.
    uint24 expected = uint24(lowest.alphaPips + lowest.betaPips * delta / BETA_DENOMINATOR);
    assertEq(curve.getProtocolFee(key), expected << 12 | expected);
  }

  function testFuzz_getProtocolFee_WhenTheLPFeeIsInAHigherBucket(
    PoolKey memory key,
    FeeBucket[16] memory raw,
    uint256 count,
    uint256 index
  ) public {
    // Given: two or more fee buckets.
    count = bound(count, 2, 16);
    FeeBucket[] memory buckets = _boundFeeBuckets(raw, count);

    // When: the pool has a static LP fee in a bucket above bucket 0.
    index = bound(index, 1, count - 1);
    uint256 ceiling =
      index + 1 < count ? buckets[index + 1].lpFeeFloor - 1 : LPFeeLibrary.MAX_LP_FEE;
    key.fee = uint24(bound(key.fee, buckets[index].lpFeeFloor, ceiling));

    // Given: the slope of that bucket keeps the fee at or below MAX_PROTOCOL_FEE.
    FeeBucket memory bucket = buckets[index];
    uint256 delta = key.fee - bucket.lpFeeFloor;
    if (delta > 0) {
      uint256 maxBeta =
        (ProtocolFeeLibrary.MAX_PROTOCOL_FEE - bucket.alphaPips) * BETA_DENOMINATOR / delta;
      bucket.betaPips = uint32(bound(bucket.betaPips, 0, maxBeta));
    }
    V4StaticCurveRuleset curve = new V4StaticCurveRuleset(buckets);

    // Then: getProtocolFee calculates the fee from that bucket.
    uint24 expected = uint24(bucket.alphaPips + bucket.betaPips * delta / BETA_DENOMINATOR);
    assertEq(curve.getProtocolFee(key), expected << 12 | expected);
  }

  function testFuzz_getProtocolFee_WhenTheCalculatedFeeIsMoreThanMaxProtocolFee(
    PoolKey memory key,
    FeeBucket[16] memory raw,
    uint256 count
  ) public {
    // Given: fee buckets.
    count = bound(count, 1, 16);
    FeeBucket[] memory buckets = _boundFeeBuckets(raw, count);

    // When: the pool has a static LP fee 2 or more pips above the floor of the highest bucket.
    FeeBucket memory highest = buckets[count - 1];
    key.fee = uint24(bound(key.fee, highest.lpFeeFloor + 2, LPFeeLibrary.MAX_LP_FEE));

    // When: the slope of that bucket makes the fee more than MAX_PROTOCOL_FEE.
    uint256 delta = key.fee - highest.lpFeeFloor;
    uint256 minBeta =
      ((ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1 - highest.alphaPips) * BETA_DENOMINATOR + delta - 1)
        / delta;
    highest.betaPips = uint32(bound(highest.betaPips, minBeta, MAX_BETA_PIPS));
    V4StaticCurveRuleset curve = new V4StaticCurveRuleset(buckets);

    // Then: getProtocolFee returns MAX_PROTOCOL_FEE in the two directions.
    uint24 maxFee = ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
    assertEq(curve.getProtocolFee(key), maxFee << 12 | maxFee);
  }

  // ============ getFeeForLpFee ============
  //
  // getFeeForLpFee
  // ├── when the LP fee is at most MAX_LP_FEE
  // │   └── it returns the same fee as getProtocolFee
  // └── when the LP fee is above MAX_LP_FEE
  //     ├── when the calculated fee is at most MAX_PROTOCOL_FEE
  //     │   └── it returns that fee in the two directions
  //     └── when the calculated fee is more than MAX_PROTOCOL_FEE
  //         └── it returns MAX_PROTOCOL_FEE in the two directions
  //
  // An LP fee above MAX_LP_FEE is an effective fee: the static LP fee plus a fee the hook takes
  // through custom accounting. getProtocolFee reverts for the dynamic-fee flag, so that input is
  // covered here.

  function testFuzz_getFeeForLpFee_WhenTheLPFeeIsAtMostMaxLpFee(
    PoolKey memory key,
    FeeBucket[16] memory raw,
    uint256 count
  ) public {
    // Given: fee buckets.
    V4StaticCurveRuleset curve =
      new V4StaticCurveRuleset(_boundFeeBuckets(raw, bound(count, 1, 16)));

    // When: the LP fee is a static fee.
    key.fee = uint24(bound(key.fee, 0, LPFeeLibrary.MAX_LP_FEE));

    // Then: getFeeForLpFee returns the same fee as getProtocolFee.
    assertEq(curve.getFeeForLpFee(key.fee), curve.getProtocolFee(key));
  }

  function testFuzz_getFeeForLpFee_WhenTheLPFeeIsAboveMaxLpFee(
    FeeBucket[16] memory raw,
    uint256 count,
    uint24 lpFee
  ) public {
    // Given: fee buckets.
    count = bound(count, 1, 16);
    FeeBucket[] memory buckets = _boundFeeBuckets(raw, count);

    // When: the LP fee is above MAX_LP_FEE, in the highest bucket.
    FeeBucket memory highest = buckets[count - 1];
    lpFee = uint24(bound(lpFee, LPFeeLibrary.MAX_LP_FEE + 1, type(uint24).max));

    // Given: the slope of that bucket keeps the fee at or below MAX_PROTOCOL_FEE.
    uint256 delta = lpFee - highest.lpFeeFloor;
    uint256 maxBeta =
      (ProtocolFeeLibrary.MAX_PROTOCOL_FEE - highest.alphaPips) * BETA_DENOMINATOR / delta;
    highest.betaPips = uint32(bound(highest.betaPips, 0, maxBeta));
    V4StaticCurveRuleset curve = new V4StaticCurveRuleset(buckets);

    // Then: getFeeForLpFee returns that fee in the two directions.
    uint24 expected = uint24(highest.alphaPips + highest.betaPips * delta / BETA_DENOMINATOR);
    assertEq(curve.getFeeForLpFee(lpFee), expected << 12 | expected);
  }

  function testFuzz_getFeeForLpFee_WhenTheCalculatedFeeIsMoreThanMaxProtocolFee(
    FeeBucket[16] memory raw,
    uint256 count,
    uint24 lpFee
  ) public {
    // Given: fee buckets.
    count = bound(count, 1, 16);
    FeeBucket[] memory buckets = _boundFeeBuckets(raw, count);

    // When: the LP fee is above MAX_LP_FEE and 2 or more pips above the floor of the highest
    // bucket.
    FeeBucket memory highest = buckets[count - 1];
    uint24 floor = highest.lpFeeFloor + 2 > LPFeeLibrary.MAX_LP_FEE + 1
      ? highest.lpFeeFloor + 2
      : LPFeeLibrary.MAX_LP_FEE + 1;
    lpFee = uint24(bound(lpFee, floor, type(uint24).max));

    // When: the slope of that bucket makes the fee more than MAX_PROTOCOL_FEE.
    uint256 delta = lpFee - highest.lpFeeFloor;
    uint256 minBeta =
      ((ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1 - highest.alphaPips) * BETA_DENOMINATOR + delta - 1)
        / delta;
    highest.betaPips = uint32(bound(highest.betaPips, minBeta, MAX_BETA_PIPS));
    V4StaticCurveRuleset curve = new V4StaticCurveRuleset(buckets);

    // Then: getFeeForLpFee returns MAX_PROTOCOL_FEE in the two directions.
    uint24 maxFee = ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
    assertEq(curve.getFeeForLpFee(lpFee), maxFee << 12 | maxFee);
  }

  // ============ feeBucketsLength ============
  //
  // feeBucketsLength
  // └── it returns the number of fee buckets

  function testFuzz_feeBucketsLength(FeeBucket[16] memory raw, uint256 count) public {
    // Given: fee buckets.
    count = bound(count, 1, 16);
    V4StaticCurveRuleset curve = new V4StaticCurveRuleset(_boundFeeBuckets(raw, count));

    // Then: feeBucketsLength returns the number of fee buckets.
    assertEq(curve.feeBucketsLength(), count);
  }

  // ============ feeBucket ============
  //
  // feeBucket
  // ├── when the index is out of bounds
  // │   └── it reverts with an index out-of-bounds panic
  // └── when the index is in bounds
  //     └── it returns the bucket at the index

  function testFuzz_feeBucket_RevertWhen_TheIndexIsOutOfBounds(
    FeeBucket[16] memory raw,
    uint256 count,
    uint256 index
  ) public {
    // Given: fee buckets.
    count = bound(count, 1, 16);
    V4StaticCurveRuleset curve = new V4StaticCurveRuleset(_boundFeeBuckets(raw, count));

    // When: the index is out of bounds.
    index = bound(index, count, type(uint256).max);

    // Then: feeBucket reverts with an index out-of-bounds panic.
    vm.expectRevert(stdError.indexOOBError);
    curve.feeBucket(index);
  }

  function testFuzz_feeBucket_WhenTheIndexIsInBounds(
    FeeBucket[16] memory raw,
    uint256 count,
    uint256 index
  ) public {
    // Given: fee buckets.
    count = bound(count, 1, 16);
    FeeBucket[] memory buckets = _boundFeeBuckets(raw, count);
    V4StaticCurveRuleset curve = new V4StaticCurveRuleset(buckets);

    // When: the index is in bounds.
    index = bound(index, 0, count - 1);

    // Then: feeBucket returns the bucket at the index.
    (uint24 lpFeeFloor, uint24 alphaPips, uint32 betaPips) = curve.feeBucket(index);
    assertEq(lpFeeFloor, buckets[index].lpFeeFloor);
    assertEq(alphaPips, buckets[index].alphaPips);
    assertEq(betaPips, buckets[index].betaPips);
  }

  // ============ Proposal 6 curve ============
  //
  // The curve of proposal 6 gives the protocol fees that the proposal lists, in pips, at the
  // listed LP fees. Mainnet V4FeePolicy 0x1cd822b70a0591420F65E94b9B3A0D0b0fB3a314 returns the
  // same fees for LP fees of 100, 500, 3000 and 10_000.

  function test_proposal6Curve_givesTheListedFees() public {
    V4StaticCurveRuleset curve = new V4StaticCurveRuleset(_proposal6Buckets());

    uint24[10] memory lpFees = [uint24(0), 3, 75, 100, 375, 500, 2500, 3000, 8334, 10_000];
    uint24[10] memory fees = [uint24(1), 1, 20, 25, 100, 125, 400, 500, 1000, 1000];
    for (uint256 i; i < lpFees.length; ++i) {
      assertEq(curve.getFeeForLpFee(lpFees[i]), fees[i] << 12 | fees[i]);
    }
  }
}
