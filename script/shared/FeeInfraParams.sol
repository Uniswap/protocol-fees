// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {
  FeeBucket,
  FlagRule,
  HookFamilyAssignment,
  PairClassFeeAssignment
} from "../../src/interfaces/IV4FeePolicy.sol";

/// @dev Fee tiers `V3OpenFeeAdapter` is configured for, in the order `v3FeeTierDefaults` uses.
uint24 constant V3_TIER_100 = 100;
uint24 constant V3_TIER_500 = 500;
uint24 constant V3_TIER_3000 = 3000;
uint24 constant V3_TIER_10000 = 10_000;

/// @dev Consistency level 202 is what Wormhole's own deployment scripts use; the three
/// custom-consistency parameters are only read when the level is 203.
uint8 constant CONSISTENCY_LEVEL = 202;

/// @dev Everything the fee infra needs from the chain and from governance's fee decisions. Fee
/// values arrive in the form the contracts store: v3 values packed per tier, v4 values packed
/// into both swap directions and, for aggregator hooks, already divided by 25. Lists arrive
/// parsed and, for pairs, sorted.
///
/// Whatever deploys the fee infra holds none of these values itself, so the params are the whole
/// configuration and the thing to check the result against.
struct FeeInfraParams {
  /// @dev Uniswap V3 Factory on this chain.
  address v3Factory;
  /// @dev Uniswap V4 Pool Manager on this chain.
  address poolManager;
  /// @dev Governance's account on this chain, which ends up owning everything.
  address receiver;
  /// @dev Minimum amount of the releaser's resource required to release.
  uint256 releaserThreshold;
  /// @dev `V3OpenFeeAdapter` default, applied when no tier default is set.
  uint8 v3DefaultFee;
  /// @dev `V3OpenFeeAdapter` per-tier defaults, in tier order 100, 500, 3000, 10000.
  uint8[4] v3FeeTierDefaults;
  /// @dev `V4FeePolicy` fee buckets, ordered by ascending `lpFeeFloor`.
  FeeBucket[] feeBuckets;
  /// @dev `V4FeePolicy` flag rules, mapping self-reported hook flags to families.
  FlagRule[] flagRules;
  /// @dev Family whose default is set; the aggregator hook family.
  uint8 aggHookFamilyId;
  /// @dev Stored aggregator hook family default, packed into both swap directions.
  uint24 aggHookDefaultFee;
  /// @dev Hooks assigned to a family by address. May be empty.
  HookFamilyAssignment[] hookFamilies;
  /// @dev Pair-level fees for the aggregator family. May be empty.
  PairClassFeeAssignment[] pairClassFees;
}

/// @dev Everything the Wormhole infra needs from the chain. Every other value is the same on
/// every chain.
struct WormholeInfraParams {
  /// @dev Wormhole-defined chain id of this chain, not the EIP-155 one.
  uint16 wormholeChainId;
  /// @dev Wormhole-defined chain id of Ethereum.
  uint16 ethereumWormholeChainId;
  /// @dev Wormhole core bridge on this chain.
  address wormholeCore;
  /// @dev NttManager proxy on Ethereum, registered as this chain's peer.
  address ethereumNttManager;
  /// @dev WormholeTransceiver proxy on Ethereum, registered as this chain's peer.
  address ethereumWormholeTransceiver;
  /// @dev Governance-owned Wormhole message receiver, which ends up owning everything.
  address receiver;
  /// @dev Consistency level the transceiver publishes at.
  uint8 consistencyLevel;
}
