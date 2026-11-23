// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {PoolId} from "v4-core/types/PoolId.sol";
import {
  IStablePairHookFeeConfig,
  IVolatilePairHookFeeConfig
} from "../../src/interfaces/external/IPairHookFeeConfig.sol";

/// @notice A mock of the fee configuration getter of the StablePairHook. Only the optimal fee is
/// set per pool. The other fields have fixed values that are not zero, so a test fails if a
/// ruleset reads the wrong field.
contract MockStablePairHook is IStablePairHookFeeConfig {
  mapping(PoolId poolId => uint24) internal _optimalFeeE6;

  function setOptimalFee(PoolId poolId, uint24 optimalFeeE6) external {
    _optimalFeeE6[poolId] = optimalFeeE6;
  }

  function feeConfig(PoolId poolId)
    external
    view
    returns (uint24 k, uint24 optimalFeeE6, uint8 targetMultiplier, uint160 referenceSqrtPriceX96)
  {
    return (16_609_443, _optimalFeeE6[poolId], 50, uint160(1 << 96));
  }
}

/// @notice A mock of the fee configuration getter of the VolatilePairHook. Only the resting spread
/// is set per pool. The other fields have fixed values that are not zero, so a test fails if a
/// ruleset reads the wrong field.
contract MockVolatilePairHook is IVolatilePairHookFeeConfig {
  mapping(PoolId poolId => uint24) internal _restingSpreadE6;

  function setRestingSpread(PoolId poolId, uint24 restingSpreadE6) external {
    _restingSpreadE6[poolId] = restingSpreadE6;
  }

  function feeConfig(PoolId poolId)
    external
    view
    returns (
      uint24 restingSpreadE6,
      uint24 backrunCaptureFractionE6,
      uint24 midFadeRateE6,
      uint24 maxMidFadeE6,
      uint24 skewRateE6,
      uint24 maxSkewStepE6,
      uint24 maxSkewE6,
      uint24 backrunThresholdE6,
      uint24 restoreFractionE6,
      uint24 restoreThresholdE6
    )
  {
    return (_restingSpreadE6[poolId], 111, 222, 333, 444, 555, 666, 777, 888, 999);
  }
}
