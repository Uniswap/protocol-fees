// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

/// @title IFeeClassifiedHook
/// @notice Optional interface for v4 hooks to self-report behavioral flags for
/// protocol fee classification.
/// @dev Hooks return a uint256 bitfield of OR'd flags from HookFeeFlags. The
/// V4FeePolicy matches these flags against governance-configured rules to derive
/// a family ID. Gas-capped staticcall prevents griefing.
/// Governance can always override via setHookFamily().
/// @custom:security-contact security@uniswap.org
interface IFeeClassifiedHook {
  /// @notice Returns the hook's self-reported behavioral flags.
  /// @dev Return 0 to indicate no self-classification (falls through to defaultFee).
  /// Flags are OR'd constants from HookFeeFlags — see that library for the vocabulary.
  function protocolFeeFlags() external view returns (uint256);
}
