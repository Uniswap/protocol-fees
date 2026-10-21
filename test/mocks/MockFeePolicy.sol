// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";

/// @notice A mock of V4FeePolicy. It returns the same fee for all pools.
contract MockFeePolicy {
  uint24 internal immutable FEE;

  constructor(uint24 fee) {
    FEE = fee;
  }

  function computeFee(PoolKey calldata) external view returns (uint24) {
    return FEE;
  }
}
