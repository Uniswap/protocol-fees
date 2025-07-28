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

abstract contract SoftNonce is Nonce {
  uint256 public lastSeenTimestamp;

  uint256 public constant EXPIRATION = 30 minutes; // TODO: whats a reasonable number :thinking:

  constructor() {
    lastSeenTimestamp = block.timestamp;
  }

  /// @notice Handles an expirable (soft) nonce
  /// Continue execution if the calldata nonce is equal to the current nonce
  /// Continue execution if the calldata nonce is one greater AND the timestamp
  modifier handleSoftNonce(uint256 _nonce) {
    if (_nonce != nonce) {
      if (lastSeenTimestamp + EXPIRATION < block.timestamp) {
        // reset the nonce if it has expired
        nonce = _nonce;
      } else {
        revert InvalidNonce();
      }
    }

    lastSeenTimestamp = block.timestamp;
    unchecked {
      ++nonce;
    }
    _;
  }
}
