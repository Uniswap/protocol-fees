// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {INonce} from "../interfaces/base/INonce.sol";

abstract contract Nonce is INonce {
  /// @inheritdoc INonce
  uint256 public nonce;

  modifier handleNonce(uint256 _nonce) {
    require(_nonce == nonce, InvalidNonce());
    unchecked {
      ++nonce;
    }
    _;
  }
}
