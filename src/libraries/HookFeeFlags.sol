// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

/// @title HookFeeFlags
/// @notice Well-known behavioral flags for hook fee classification.
/// @dev Hooks OR these flags together and return the result from protocolFeeFlags().
/// The V4FeePolicy matches returned flags against governance-configured rules to
/// derive a family ID. Flags occupy a uint256; bits 0-11 are defined here with
/// room for future additions.
/// @custom:security-contact security@uniswap.org
library HookFeeFlags {
  // --- Value extraction (bits 0-3) ---
  uint256 internal constant TAKES_SWAP_SURPLUS = 1 << 0;
  uint256 internal constant TAKES_LP_SURPLUS = 1 << 1;
  uint256 internal constant USES_DYNAMIC_FEE = 1 << 2;
  uint256 internal constant REBALANCES_POOL = 1 << 3;

  // --- Strategy type (bits 4-7) ---
  uint256 internal constant STABLE_PAIR = 1 << 4;
  uint256 internal constant ORACLE_BASED = 1 << 5;
  uint256 internal constant LIMIT_ORDER = 1 << 6;
  uint256 internal constant AUCTION_BASED = 1 << 7;

  // --- Integration type (bits 8-11) ---
  uint256 internal constant LENDING_INTEGRATION = 1 << 8;
  uint256 internal constant YIELD_BEARING = 1 << 9;
  uint256 internal constant CROSS_CHAIN = 1 << 10;
  uint256 internal constant AGGREGATOR = 1 << 11;
}
