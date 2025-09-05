// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

/// @title Nonce Interface
interface INonce {
  /// @notice Thrown when a user-provided nonce is not equal to the contract's nonce
  error InvalidNonce();

  /// @return The contract's nonce
  function nonce() external view returns (uint256);
}
