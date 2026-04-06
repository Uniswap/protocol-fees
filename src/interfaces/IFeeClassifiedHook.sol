// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

/// @title IFeeClassifiedHook
/// @notice Optional interface for v4 hooks to self-report their protocol fee family.
/// @dev Hooks that implement this allow the V4FeePolicy to automatically classify them
/// without requiring a governance transaction. The policy calls protocolFeeFamily() with
/// a gas cap; if the call succeeds and returns a valid familyId, it is trusted.
/// Governance can always override via setHookFamily().
/// @custom:security-contact security@uniswap.org
interface IFeeClassifiedHook {
  /// @notice Returns the hook's self-reported fee family ID.
  /// @dev Return 0 to indicate no self-classification (falls through to defaultFee).
  /// Family IDs (1-255) are governance-defined — see documentation for semantics.
  function protocolFeeFamily() external view returns (uint8);
}
