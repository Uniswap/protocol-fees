// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

/// @title VestingLib
/// @notice Library for vesting calculations
/// @custom:security-contact security@uniswap.org
library VestingLib {
  /// if b is negative: a - (-b)
  /// otherwise: a - b
  function sub(uint256 a, int256 b) internal pure returns (uint256) {
    if (b < 0) return a + SafeCast.toUint256(-b);
    return a - SafeCast.toUint256(b);
  }

  function add(int256 a, uint256 b) internal pure returns (int256) {
    return a + SafeCast.toInt256(b);
  }
}
