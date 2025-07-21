// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

contract Nonce {
  uint256 public nonce;

  modifier handleNonce(uint256 _nonce) {
    require(_nonce == nonce);
    _;
    unchecked {
      nonce++;
    }
  }
}
