// SPDX-License-Identifier: AGPl-3.0-only
pragma solidity 0.8.29;

import {FlagRule, FamilyDefaultAssignment} from "../../src/interfaces/IV4FeePolicy.sol";

// ─── Existing families (unchanged from proposal-6) ───

uint8 constant AGG_HOOK_ID = 11;
uint256 constant AGG_HOOK_FAMILY = 1 << AGG_HOOK_ID;

// ─── Native math self-opt-in ───

/// @dev Flag bit 255 lets a hook self-opt into the native-math fee schedule (fee buckets
/// keyed on the pool's static LP fee). Family ID 255 is V4FeePolicy.NATIVE_MATH_FAMILY_ID;
/// dynamic-fee pools that opt in fall through to defaultFee (the policy's dynamic-fee guard).
uint8 constant NATIVE_MATH_ID = 255;
uint256 constant NATIVE_MATH_OPT_IN_FLAG = 1 << NATIVE_MATH_ID;

/// @title FamilyTiers
/// @notice Fixed protocol-fee tier families hooks can self-opt into via protocolFeeFlags().
/// @dev Convention: family ID == flag bit index (matches the aggregator family at bit 11).
/// Tiers occupy IDs/bits 20-31, ascending by fee.
///
/// | Family ID | Flag Bit  | Fee (pips/direction) |
/// | --------- | --------- | -------------------- |
/// | `20`      | `1 << 20` | 10                   |
/// | `21`      | `1 << 21` | 50                   |
/// | `22`      | `1 << 22` | 100                  |
/// | `23`      | `1 << 23` | 200                  |
/// | `24`      | `1 << 24` | 300                  |
/// | `25`      | `1 << 25` | 400                  |
/// | `26`      | `1 << 26` | 500                  |
/// | `27`      | `1 << 27` | 600                  |
/// | `28`      | `1 << 28` | 700                  |
/// | `29`      | `1 << 29` | 800                  |
/// | `30`      | `1 << 30` | 900                  |
/// | `31`      | `1 << 31` | 1000 (cap)           |
library FamilyTiers {
  uint8 internal constant FIRST_TIER_ID = 20;
  uint256 internal constant TIER_COUNT = 12;

  /// @dev Per-direction protocol fee in pips (1 pip = 0.0001%) for each tier, ascending.
  /// 1000 = ProtocolFeeLibrary.MAX_PROTOCOL_FEE (0.1% per direction).
  function feePips() internal pure returns (uint24[12] memory) {
    return [uint24(10), 50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000];
  }

  /// @dev Family ID (== flag bit index) for tier `index`.
  function tierId(uint256 index) internal pure returns (uint8) {
    return uint8(FIRST_TIER_ID + index);
  }

  /// @dev Full flag rule set in priority order. First matching rule wins, so: aggregator
  /// keeps its existing priority, tiers run descending (a hook signaling multiple tiers
  /// pays the highest — misconfiguration must not underpay; governance can correct down),
  /// and the native-math opt-in is last so an explicit tier choice beats it. All rules are
  /// single-bit, so the descending-popcount ordering setFlagRules enforces holds trivially.
  function flagRules() internal pure returns (FlagRule[] memory rules) {
    rules = new FlagRule[](2 + TIER_COUNT);
    rules[0] = FlagRule({requiredFlags: AGG_HOOK_FAMILY, familyId: AGG_HOOK_ID});
    for (uint256 i; i < TIER_COUNT; ++i) {
      uint8 id = tierId(TIER_COUNT - 1 - i);
      rules[1 + i] = FlagRule({requiredFlags: uint256(1) << id, familyId: id});
    }
    rules[1 + TIER_COUNT] =
      FlagRule({requiredFlags: NATIVE_MATH_OPT_IN_FLAG, familyId: NATIVE_MATH_ID});
  }

  /// @dev Family default assignments for all tiers (sentinel-encoded two-direction fee).
  function familyDefaults() internal pure returns (FamilyDefaultAssignment[] memory assignments) {
    uint24[12] memory fees = feePips();
    assignments = new FamilyDefaultAssignment[](TIER_COUNT);
    for (uint256 i; i < TIER_COUNT; ++i) {
      assignments[i] = FamilyDefaultAssignment({familyId: tierId(i), feeValue: encodeFee(fees[i])});
    }
  }

  /// @dev Handles v4 fee two way encoding.
  function encodeFee(uint24 fee) internal pure returns (uint24) {
    return fee << 12 | fee;
  }
}
