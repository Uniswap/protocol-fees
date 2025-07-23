// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

abstract contract Nonce {
  uint256 public nonce;

  error InvalidNonce();

  modifier handleNonce(uint256 _nonce) {
    require(_nonce == nonce, InvalidNonce());
    unchecked {
      ++nonce;
    }
    _;
  }
}
