// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

/// @title HookFeeFlags (test scaffolding)
/// @notice Arbitrary named bits used by the flag-rule tests to construct mock hook
/// self-reports and `FlagRule.requiredFlags`.
/// @dev NOT shipped with the protocol. The policy ascribes no meaning to any bit — it
/// only checks that a rule's `requiredFlags` are a subset of the hook's returned
/// `uint256`. These constants exist purely so the tests read clearly; their specific
/// bit positions are irrelevant beyond being distinct. The real-world flag vocabulary
/// is documented in `docs/V4FeePolicy-governance-guide.md`, not enumerated onchain.
library HookFeeFlags {
  uint256 internal constant TAKES_SWAP_SURPLUS = 1 << 0;
  uint256 internal constant STABLE_PAIR = 1 << 4;
  uint256 internal constant ORACLE_BASED = 1 << 5;
  uint256 internal constant YIELD_BEARING = 1 << 9;
}
