// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test, stdError} from "forge-std/Test.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";

import {V4StaticCurveRuleset} from "../src/feeAdapters/examples/V4StaticCurveRuleset.sol";
import {IV4StaticCurveRuleset, FeeBucket} from "../src/interfaces/IV4StaticCurveRuleset.sol";

/// @dev Each section starts with the branch tree of one function. The tests are in the same
/// sequence as the tree. Each test sets all conditions of its branch, thus setUp has no bucket
/// state.
contract V4StaticCurveRulesetTest is Test {
  /// @dev The maximum `betaPips` of a bucket. At this slope, a delta of 1 pip gives
  /// MAX_PROTOCOL_FEE.
  uint32 internal constant MAX_BETA_PIPS = 1_000_000_000;

  /// @dev The denominator of `betaPips`. A slope of 1_000_000 adds 1 pip of fee for each pip of
  /// LP fee.
  uint256 internal constant BETA_DENOMINATOR = 1_000_000;

  V4StaticCurveRuleset public curve;

  address public owner;
  address public feeSetter;

  function setUp() public {
    owner = makeAddr("owner");
    feeSetter = makeAddr("feeSetter");
    curve = new V4StaticCurveRuleset(owner, feeSetter);
  }

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

  // ============ constructor ============
  //
  // constructor
  // └── it sets the owner and the fee setter, with no fee buckets

  function testFuzz_constructor(address initialOwner, address initialFeeSetter) public {
    vm.expectEmit();
    emit Owned.OwnershipTransferred(address(0), initialOwner);
    V4StaticCurveRuleset deployed = new V4StaticCurveRuleset(initialOwner, initialFeeSetter);

    assertEq(deployed.owner(), initialOwner);
    assertEq(deployed.feeSetter(), initialFeeSetter);
    assertEq(deployed.feeBucketsLength(), 0);
  }

  // ============ getProtocolFee ============
  //
  // getProtocolFee
  // ├── when the pool has a dynamic LP fee
  // │   └── it reverts with DynamicFeeNotSupported
  // └── when the pool has a static LP fee
  //     ├── given no fee buckets are set
  //     │   └── it returns zero
  //     └── given fee buckets are set
  //         ├── when the LP fee is below the floor of bucket 0
  //         │   └── it returns the alpha of bucket 0 in the two directions
  //         ├── when the LP fee is in bucket 0
  //         │   └── it calculates the fee from bucket 0
  //         ├── when the LP fee is in a higher bucket
  //         │   └── it calculates the fee from that bucket
  //         └── when the calculated fee is more than MAX_PROTOCOL_FEE
  //             └── it returns MAX_PROTOCOL_FEE in the two directions
  //
  // The LP fee is in bucket k when it is at or above the floor of bucket k and below the floor of
  // bucket k + 1. In each swap direction, the calculated fee is
  // alpha + beta * (LP fee - floor) / 1_000_000.

  function testFuzz_getProtocolFee_RevertWhen_ThePoolHasADynamicLPFee(
    PoolKey memory key,
    FeeBucket[16] memory raw,
    uint256 count
  ) public {
    // Given: fee buckets are set.
    vm.prank(feeSetter);
    curve.setFeeBuckets(_boundFeeBuckets(raw, bound(count, 1, 16)));

    // When: the pool has a dynamic LP fee.
    key.fee = LPFeeLibrary.DYNAMIC_FEE_FLAG;

    // Then: getProtocolFee reverts with DynamicFeeNotSupported.
    vm.expectRevert(IV4StaticCurveRuleset.DynamicFeeNotSupported.selector);
    curve.getProtocolFee(key);
  }

  function testFuzz_getProtocolFee_GivenNoFeeBucketsAreSet(PoolKey memory key) public view {
    // When: the pool has a static LP fee.
    key.fee = uint24(bound(key.fee, 0, LPFeeLibrary.MAX_LP_FEE));

    // Given: no fee buckets are set.
    // Then: getProtocolFee returns zero.
    assertEq(curve.getProtocolFee(key), 0);
  }

  function testFuzz_getProtocolFee_WhenTheLPFeeIsBelowTheFloorOfBucket0(
    PoolKey memory key,
    FeeBucket[16] memory raw,
    uint256 count
  ) public {
    // Given: fee buckets are set, and the floor of bucket 0 is more than zero.
    raw[0].lpFeeFloor = uint24(bound(raw[0].lpFeeFloor, 1, 100_000));
    FeeBucket[] memory buckets = _boundFeeBuckets(raw, bound(count, 1, 16));
    vm.prank(feeSetter);
    curve.setFeeBuckets(buckets);

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
    vm.prank(feeSetter);
    curve.setFeeBuckets(buckets);

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
    vm.prank(feeSetter);
    curve.setFeeBuckets(buckets);

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
    vm.prank(feeSetter);
    curve.setFeeBuckets(buckets);

    // Then: getProtocolFee returns MAX_PROTOCOL_FEE in the two directions.
    uint24 maxFee = ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
    assertEq(curve.getProtocolFee(key), maxFee << 12 | maxFee);
  }

  // ============ getFeeForLpFee ============
  //
  // getFeeForLpFee
  // ├── given no fee buckets are set
  // │   └── it returns zero
  // └── given fee buckets are set
  //     ├── when the LP fee is at most MAX_LP_FEE
  //     │   └── it returns the same fee as getProtocolFee
  //     └── when the LP fee is above MAX_LP_FEE
  //         ├── when the calculated fee is at most MAX_PROTOCOL_FEE
  //         │   └── it returns that fee in the two directions
  //         └── when the calculated fee is more than MAX_PROTOCOL_FEE
  //             └── it returns MAX_PROTOCOL_FEE in the two directions
  //
  // An LP fee above MAX_LP_FEE is an effective fee: the static LP fee plus a fee the hook takes
  // through custom accounting. getProtocolFee reverts for the dynamic-fee flag, so that input is
  // covered here.

  function testFuzz_getFeeForLpFee_GivenNoFeeBucketsAreSet(uint24 lpFee) public view {
    // Given: no fee buckets are set.
    // Then: getFeeForLpFee returns zero.
    assertEq(curve.getFeeForLpFee(lpFee), 0);
  }

  function testFuzz_getFeeForLpFee_WhenTheLPFeeIsAtMostMaxLpFee(
    PoolKey memory key,
    FeeBucket[16] memory raw,
    uint256 count
  ) public {
    // Given: fee buckets are set.
    vm.prank(feeSetter);
    curve.setFeeBuckets(_boundFeeBuckets(raw, bound(count, 1, 16)));

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
    // Given: fee buckets are set.
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
    vm.prank(feeSetter);
    curve.setFeeBuckets(buckets);

    // Then: getFeeForLpFee returns that fee in the two directions.
    uint24 expected = uint24(highest.alphaPips + highest.betaPips * delta / BETA_DENOMINATOR);
    assertEq(curve.getFeeForLpFee(lpFee), expected << 12 | expected);
  }

  function testFuzz_getFeeForLpFee_WhenTheCalculatedFeeIsMoreThanMaxProtocolFee(
    FeeBucket[16] memory raw,
    uint256 count,
    uint24 lpFee
  ) public {
    // Given: fee buckets are set.
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
    vm.prank(feeSetter);
    curve.setFeeBuckets(buckets);

    // Then: getFeeForLpFee returns MAX_PROTOCOL_FEE in the two directions.
    uint24 maxFee = ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
    assertEq(curve.getFeeForLpFee(lpFee), maxFee << 12 | maxFee);
  }

  // ============ feeBucketsLength ============
  //
  // feeBucketsLength
  // └── it returns the number of fee buckets

  function testFuzz_feeBucketsLength(FeeBucket[16] memory raw, uint256 count) public {
    // Given: fee buckets are set.
    count = bound(count, 1, 16);
    vm.prank(feeSetter);
    curve.setFeeBuckets(_boundFeeBuckets(raw, count));

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
    // Given: fee buckets are set.
    count = bound(count, 1, 16);
    vm.prank(feeSetter);
    curve.setFeeBuckets(_boundFeeBuckets(raw, count));

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
    // Given: fee buckets are set.
    count = bound(count, 1, 16);
    FeeBucket[] memory buckets = _boundFeeBuckets(raw, count);
    vm.prank(feeSetter);
    curve.setFeeBuckets(buckets);

    // When: the index is in bounds.
    index = bound(index, 0, count - 1);

    // Then: feeBucket returns the bucket at the index.
    (uint24 lpFeeFloor, uint24 alphaPips, uint32 betaPips) = curve.feeBucket(index);
    assertEq(lpFeeFloor, buckets[index].lpFeeFloor);
    assertEq(alphaPips, buckets[index].alphaPips);
    assertEq(betaPips, buckets[index].betaPips);
  }

  // ============ setFeeSetter ============
  //
  // setFeeSetter
  // ├── when the caller is not the owner
  // │   └── it reverts with UNAUTHORIZED
  // └── when the caller is the owner
  //     ├── it sets the fee setter
  //     └── it emits FeeSetterUpdated

  function testFuzz_setFeeSetter_RevertWhen_CallerIsNotTheOwner(
    address caller,
    address newFeeSetter
  ) public {
    // When: the caller is not the owner.
    vm.assume(caller != owner);

    // Then: setFeeSetter reverts with UNAUTHORIZED.
    vm.prank(caller);
    vm.expectRevert("UNAUTHORIZED");
    curve.setFeeSetter(newFeeSetter);
  }

  function testFuzz_setFeeSetter_WhenCallerIsTheOwner(address newFeeSetter) public {
    // When: the caller is the owner.
    // Then: setFeeSetter emits FeeSetterUpdated.
    vm.expectEmit(address(curve));
    emit IV4StaticCurveRuleset.FeeSetterUpdated(feeSetter, newFeeSetter);
    vm.prank(owner);
    curve.setFeeSetter(newFeeSetter);

    // Then: setFeeSetter sets the fee setter.
    assertEq(curve.feeSetter(), newFeeSetter);
  }

  // ============ setFeeBuckets ============
  //
  // setFeeBuckets
  // ├── when the caller is not the fee setter
  // │   └── it reverts with Unauthorized
  // └── when the caller is the fee setter
  //     ├── when there are no buckets
  //     │   └── it reverts with EmptyBuckets
  //     ├── when there are more than 16 buckets
  //     │   └── it reverts with TooManyBuckets
  //     └── when there are 1 to 16 buckets
  //         ├── when a floor is not higher than the previous floor
  //         │   └── it reverts with BucketsNotAscending
  //         ├── when an alpha is more than MAX_PROTOCOL_FEE
  //         │   └── it reverts with InvalidFeeValue
  //         ├── when a beta is more than MAX_BETA_PIPS
  //         │   └── it reverts with MultiplierTooLarge
  //         └── when all buckets are correct
  //             ├── it replaces the fee buckets
  //             └── it emits FeeBucketsUpdated with the number of buckets

  function testFuzz_setFeeBuckets_RevertWhen_CallerIsNotTheFeeSetter(
    address caller,
    FeeBucket[16] memory raw,
    uint256 count
  ) public {
    // When: the caller is not the fee setter.
    vm.assume(caller != feeSetter);
    FeeBucket[] memory buckets = _boundFeeBuckets(raw, bound(count, 1, 16));

    // Then: setFeeBuckets reverts with Unauthorized.
    vm.prank(caller);
    vm.expectRevert(IV4StaticCurveRuleset.Unauthorized.selector);
    curve.setFeeBuckets(buckets);
  }

  function test_setFeeBuckets_RevertWhen_ThereAreNoBuckets() public {
    // When: the caller is the fee setter, and there are no buckets.
    // Then: setFeeBuckets reverts with EmptyBuckets.
    vm.prank(feeSetter);
    vm.expectRevert(IV4StaticCurveRuleset.EmptyBuckets.selector);
    curve.setFeeBuckets(new FeeBucket[](0));
  }

  function testFuzz_setFeeBuckets_RevertWhen_ThereAreMoreThan16Buckets(uint256 count) public {
    // When: the caller is the fee setter, and there are more than 16 buckets with higher floors.
    count = bound(count, 17, 64);
    FeeBucket[] memory buckets = new FeeBucket[](count);
    for (uint256 i; i < count; ++i) {
      buckets[i].lpFeeFloor = uint24(i);
    }

    // Then: setFeeBuckets reverts with TooManyBuckets.
    vm.prank(feeSetter);
    vm.expectRevert(IV4StaticCurveRuleset.TooManyBuckets.selector);
    curve.setFeeBuckets(buckets);
  }

  function testFuzz_setFeeBuckets_RevertWhen_AFloorIsNotHigherThanThePreviousFloor(
    FeeBucket[16] memory raw,
    uint256 count,
    uint256 index,
    uint24 lpFeeFloor
  ) public {
    // When: the caller is the fee setter, and there are 2 to 16 buckets.
    count = bound(count, 2, 16);
    FeeBucket[] memory buckets = _boundFeeBuckets(raw, count);

    // When: the floor of one bucket is not higher than the previous floor.
    index = bound(index, 1, count - 1);
    buckets[index].lpFeeFloor = uint24(bound(lpFeeFloor, 0, buckets[index - 1].lpFeeFloor));

    // Then: setFeeBuckets reverts with BucketsNotAscending.
    vm.prank(feeSetter);
    vm.expectRevert(IV4StaticCurveRuleset.BucketsNotAscending.selector);
    curve.setFeeBuckets(buckets);
  }

  function testFuzz_setFeeBuckets_RevertWhen_AnAlphaIsMoreThanMaxProtocolFee(
    FeeBucket[16] memory raw,
    uint256 count,
    uint256 index,
    uint24 alphaPips
  ) public {
    // When: the caller is the fee setter, and there are 1 to 16 buckets.
    count = bound(count, 1, 16);
    FeeBucket[] memory buckets = _boundFeeBuckets(raw, count);

    // When: the alpha of one bucket is more than MAX_PROTOCOL_FEE.
    index = bound(index, 0, count - 1);
    buckets[index].alphaPips =
      uint24(bound(alphaPips, ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1, type(uint24).max));

    // Then: setFeeBuckets reverts with InvalidFeeValue.
    vm.prank(feeSetter);
    vm.expectRevert(IV4StaticCurveRuleset.InvalidFeeValue.selector);
    curve.setFeeBuckets(buckets);
  }

  function testFuzz_setFeeBuckets_RevertWhen_ABetaIsMoreThanMaxBetaPips(
    FeeBucket[16] memory raw,
    uint256 count,
    uint256 index,
    uint32 betaPips
  ) public {
    // When: the caller is the fee setter, and there are 1 to 16 buckets.
    count = bound(count, 1, 16);
    FeeBucket[] memory buckets = _boundFeeBuckets(raw, count);

    // When: the beta of one bucket is more than MAX_BETA_PIPS.
    index = bound(index, 0, count - 1);
    buckets[index].betaPips = uint32(bound(betaPips, MAX_BETA_PIPS + 1, type(uint32).max));

    // Then: setFeeBuckets reverts with MultiplierTooLarge.
    vm.prank(feeSetter);
    vm.expectRevert(IV4StaticCurveRuleset.MultiplierTooLarge.selector);
    curve.setFeeBuckets(buckets);
  }

  function testFuzz_setFeeBuckets_WhenAllBucketsAreCorrect(
    FeeBucket[16] memory previousRaw,
    uint256 previousCount,
    FeeBucket[16] memory raw,
    uint256 count
  ) public {
    // Given: fee buckets are set.
    vm.prank(feeSetter);
    curve.setFeeBuckets(_boundFeeBuckets(previousRaw, bound(previousCount, 1, 16)));

    // When: the caller is the fee setter, and all of the 1 to 16 new buckets are correct.
    FeeBucket[] memory buckets = _boundFeeBuckets(raw, bound(count, 1, 16));

    // Then: setFeeBuckets emits FeeBucketsUpdated with the number of buckets.
    vm.expectEmit(address(curve));
    emit IV4StaticCurveRuleset.FeeBucketsUpdated(buckets.length);
    vm.prank(feeSetter);
    curve.setFeeBuckets(buckets);

    // Then: setFeeBuckets replaces the fee buckets.
    assertEq(curve.feeBucketsLength(), buckets.length);
    for (uint256 i; i < buckets.length; ++i) {
      (uint24 lpFeeFloor, uint24 alphaPips, uint32 betaPips) = curve.feeBucket(i);
      assertEq(lpFeeFloor, buckets[i].lpFeeFloor);
      assertEq(alphaPips, buckets[i].alphaPips);
      assertEq(betaPips, buckets[i].betaPips);
    }
  }

  // ============ clearFeeBuckets ============
  //
  // clearFeeBuckets
  // ├── when the caller is not the fee setter
  // │   └── it reverts with Unauthorized
  // └── when the caller is the fee setter
  //     ├── it removes all fee buckets, thus the fee of a static-fee pool is zero
  //     └── it emits FeeBucketsUpdated with zero

  function testFuzz_clearFeeBuckets_RevertWhen_CallerIsNotTheFeeSetter(address caller) public {
    // When: the caller is not the fee setter.
    vm.assume(caller != feeSetter);

    // Then: clearFeeBuckets reverts with Unauthorized.
    vm.prank(caller);
    vm.expectRevert(IV4StaticCurveRuleset.Unauthorized.selector);
    curve.clearFeeBuckets();
  }

  function testFuzz_clearFeeBuckets_WhenCallerIsTheFeeSetter(
    PoolKey memory key,
    FeeBucket[16] memory raw,
    uint256 count
  ) public {
    // Given: fee buckets are set.
    vm.prank(feeSetter);
    curve.setFeeBuckets(_boundFeeBuckets(raw, bound(count, 1, 16)));

    // When: the caller is the fee setter.
    // Then: clearFeeBuckets emits FeeBucketsUpdated with zero.
    vm.expectEmit(address(curve));
    emit IV4StaticCurveRuleset.FeeBucketsUpdated(0);
    vm.prank(feeSetter);
    curve.clearFeeBuckets();

    // Then: clearFeeBuckets removes all fee buckets, thus the fee of a static-fee pool is zero.
    assertEq(curve.feeBucketsLength(), 0);
    key.fee = uint24(bound(key.fee, 0, LPFeeLibrary.MAX_LP_FEE));
    assertEq(curve.getProtocolFee(key), 0);
  }

  // ============ transferOwnership ============
  //
  // transferOwnership
  // ├── when the caller is not the owner
  // │   └── it reverts with UNAUTHORIZED
  // └── when the caller is the owner
  //     ├── it sets the owner
  //     └── it emits OwnershipTransferred

  function testFuzz_transferOwnership_RevertWhen_CallerIsNotTheOwner(
    address caller,
    address newOwner
  ) public {
    // When: the caller is not the owner.
    vm.assume(caller != owner);

    // Then: transferOwnership reverts with UNAUTHORIZED.
    vm.prank(caller);
    vm.expectRevert("UNAUTHORIZED");
    curve.transferOwnership(newOwner);
  }

  function testFuzz_transferOwnership_WhenCallerIsTheOwner(address newOwner) public {
    // When: the caller is the owner.
    // Then: transferOwnership emits OwnershipTransferred.
    vm.expectEmit(address(curve));
    emit Owned.OwnershipTransferred(owner, newOwner);
    vm.prank(owner);
    curve.transferOwnership(newOwner);

    // Then: transferOwnership sets the owner.
    assertEq(curve.owner(), newOwner);
  }
}
