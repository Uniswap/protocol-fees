// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

abstract contract DecayingThreshold {
  using FixedPointMathLib for uint256;

  /// @notice the base threshold amount
  uint256 public amount;

  /// @notice the last timestamp an action occurred
  uint256 public lastCalled;

  /// @notice the expected time difference between calls, expressed in seconds
  uint256 public targetRate;

  /// @notice the rate at which the threshold decays, wei units per second
  uint256 public decayRate = 1000;

  uint256 public increaseRate = 1.1e18; // 10% increase
  uint256 public decreaseRate = 0.9e18; // 10% decrease

  constructor(uint256 _initialAmount, uint256 _targetRate) {
    amount = _initialAmount;
    targetRate = _targetRate;
    lastCalled = block.timestamp;
  }

  function getThreshold() external view returns (uint256) {
    uint256 timeDifference;
    unchecked {
      timeDifference = block.timestamp - lastCalled;
    }

    if (timeDifference < targetRate) return amount;

    uint256 threshold = amount - (timeDifference - targetRate) * decayRate;

    return threshold;
  }

  function _setLastCalled() internal {
    uint256 timeDifference;
    unchecked {
      timeDifference = block.timestamp - lastCalled;
    }

    lastCalled = block.timestamp;

    if (timeDifference < targetRate) amount = amount.mulWadDown(increaseRate);
    else if (timeDifference > targetRate) amount = amount.mulWadDown(decreaseRate);
  }
}
