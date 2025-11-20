// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {INonce} from "../interfaces/base/INonce.sol";

/// @title Nonce
/// @notice An abstract contract that provides nonce validation for transaction ordering protection
/// @dev Implements sequential nonce validation to prevent front-running and ensure searchers
///      can guarantee their transaction order when claiming available tokens
abstract contract Nonce is INonce {
  /// @inheritdoc INonce
  uint256 public nonce;

  /// @notice Validates and increments the nonce for transaction ordering protection
  /// @dev Ensures transactions are processed in the expected order, preventing front-running
  ///      when searchers submit burns to claim available tokens. The nonce guarantees that
  ///      if a searcher sees tokens available at a specific nonce, they can claim them
  ///      without another transaction landing first. Reverts with InvalidNonce if the
  ///      provided nonce doesn't match the current contract nonce.
  /// @param _nonce The expected current nonce value
  modifier handleNonce(uint256 _nonce) {
    require(_nonce == nonce, InvalidNonce());
    unchecked {
      ++nonce;
    }
    _;
  }
}
