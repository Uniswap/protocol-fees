// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Currency} from "v4-core/types/Currency.sol";

import {FeeBucket, FlagRule, PairClassFeeAssignment} from "../../src/interfaces/IV4FeePolicy.sol";
import {Lists, Pair} from "./Lists.sol";

/// @dev The protocol fee schedule governance has set on every chain where fees are live: the v3
/// tier defaults, and the v4 buckets, flag rule, and aggregator hook family from proposal 6. A
/// chain that departs from it, as Base did on the aggregator fee, overrides at the call site.
///
/// Also the encoding helpers the schedule needs: v4 fees packed into both swap directions, pairs
/// sorted and hashed the way `V4FeePolicy` keys them.
library FeeSchedule {
  // ─── V3 ───

  /// @dev Protocol fee per tier (`V3_TIER_100` and so on, in `FeeInfraParams.sol`), packed as
  /// (1/x for token0) << 4 | (1/x for token1).
  uint8 constant V3_FEE_100 = (4 << 4) | 4; // 1/4 for 0.01% tier
  uint8 constant V3_FEE_500 = (4 << 4) | 4; // 1/4 for 0.05% tier
  uint8 constant V3_FEE_3000 = (6 << 4) | 6; // 1/6 for 0.30% tier
  uint8 constant V3_FEE_10000 = (6 << 4) | 6; // 1/6 for 1.00% tier

  /// @dev `V3OpenFeeAdapter` default, applied when no tier default is set.
  uint8 constant V3_DEFAULT_FEE = V3_FEE_100;

  /// @dev Per-tier defaults, in tier order: `V3_TIER_100`, `V3_TIER_500`, `V3_TIER_3000`,
  /// `V3_TIER_10000`.
  function v3FeeTierDefaults() internal pure returns (uint8[4] memory) {
    return [V3_FEE_100, V3_FEE_500, V3_FEE_3000, V3_FEE_10000];
  }

  // ─── V4 ───

  /// @dev Aggregator hook family: a hook whose self-reported flags include bit 11 is classified
  /// into family 11.
  uint256 constant AGG_HOOK_FLAGS = 1 << 11;
  uint8 constant AGG_HOOK_FAMILY_ID = 11;

  /// @dev Fee buckets, ordered by ascending `lpFeeFloor`.
  function feeBuckets() internal pure returns (FeeBucket[] memory buckets) {
    buckets = new FeeBucket[](8);
    buckets[0] = FeeBucket({lpFeeFloor: 0, alphaPips: 1, betaPips: 0});
    buckets[1] = FeeBucket({lpFeeFloor: 3, alphaPips: 1, betaPips: 263_889});
    buckets[2] = FeeBucket({lpFeeFloor: 75, alphaPips: 20, betaPips: 200_000});
    buckets[3] = FeeBucket({lpFeeFloor: 100, alphaPips: 25, betaPips: 272_728});
    buckets[4] = FeeBucket({lpFeeFloor: 375, alphaPips: 100, betaPips: 200_000});
    buckets[5] = FeeBucket({lpFeeFloor: 500, alphaPips: 125, betaPips: 137_500});
    buckets[6] = FeeBucket({lpFeeFloor: 2500, alphaPips: 400, betaPips: 200_000});
    buckets[7] = FeeBucket({lpFeeFloor: 5500, alphaPips: 1000, betaPips: 0});
  }

  /// @dev Flag rules. Aggregator hooks are the one hook family with a fee rule.
  ///
  /// | Name             | Family ID | Required flags |
  /// | ---------------- | --------- | -------------- |
  /// | Aggregator Hooks | `11`      | `1 << 11`      |
  function flagRules() internal pure returns (FlagRule[] memory rules) {
    rules = new FlagRule[](1);
    rules[0] = FlagRule({requiredFlags: AGG_HOOK_FLAGS, familyId: AGG_HOOK_FAMILY_ID});
  }

  /// @dev Reads a stable-stable pair list and turns it into the assignments
  /// `batchSetPairClassFee` takes: tokens sorted as the policy requires, aggregator family, `fee`
  /// packed into both swap directions.
  function pairClassFees(string memory csv, uint24 fee)
    internal
    view
    returns (PairClassFeeAssignment[] memory assignments)
  {
    Pair[] memory pairs = Lists.stableStablePairs(csv);
    assignments = new PairClassFeeAssignment[](pairs.length);
    for (uint256 i; i < pairs.length; i++) {
      (address token0, address token1) = sort(pairs[i].token0, pairs[i].token1);
      assignments[i] = PairClassFeeAssignment({
        currency0: Currency.wrap(token0),
        currency1: Currency.wrap(token1),
        familyId: AGG_HOOK_FAMILY_ID,
        feeValue: bothDirections(fee)
      });
    }
  }

  // ─── Encoding ───

  /// @dev Packs one fee into both swap directions of a v4 protocol fee: the lower 12 bits apply
  /// to zero-for-one swaps and the upper 12 bits to one-for-zero.
  function bothDirections(uint24 fee) internal pure returns (uint24) {
    return fee << 12 | fee;
  }

  /// @dev Sorts two addresses ascending, the order `V4FeePolicy` requires of a pair.
  function sort(address a, address b) internal pure returns (address, address) {
    return a < b ? (a, b) : (b, a);
  }

  /// @dev The key `V4FeePolicy` stores a sorted pair under.
  function pairHash(Currency c0, Currency c1) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(Currency.unwrap(c0), Currency.unwrap(c1)));
  }
}
