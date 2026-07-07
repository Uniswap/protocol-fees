// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

/// @title IFeeClassifiedHook
/// @notice Optional interface for v4 hooks to self-report behavioral flags for
/// protocol fee classification.
/// @dev Hooks return an opaque uint256 bitfield. The V4FeePolicy ascribes no meaning
/// to individual bits — it only matches the returned value against governance-configured
/// flag rules to derive a family ID. Gas-capped staticcall prevents griefing.
/// Governance can always override via setHookFamily(). See the governance guide for the
/// bit conventions in active use.
/// @custom:security-contact security@uniswap.org
interface IFeeClassifiedHook {
  /// @notice Returns the hook's self-reported behavioral flags.
  /// @dev Return 0 to indicate no self-classification (falls through to defaultFee).
  /// The bitfield is opaque to the policy; see the governance guide for active conventions.
  function protocolFeeFlags() external view returns (uint256);
}
