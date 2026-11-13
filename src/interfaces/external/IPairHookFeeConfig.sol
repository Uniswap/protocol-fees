// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "v4-core/types/PoolId.sol";

/// @notice The fee configuration getter of the StablePairHook.
/// @dev A subset of `IStableFeeConfiguration` in Uniswap/v4-hooks-public at commit 82de6aa
/// (`src/stable/base/StableFeeConfiguration.sol`).
interface IStablePairHookFeeConfig {
  /// @notice Returns the fee configuration of a pool.
  /// @param poolId The ID of the pool.
  /// @return k The decay factor per block, in Q24.
  /// @return optimalFeeE6 The fee that sets the width of the optimal range, in pips.
  /// @return targetMultiplier The target fee multiplier, from 0 to 100.
  /// @return referenceSqrtPriceX96 The reference price, as a sqrt Q96.
  function feeConfig(PoolId poolId)
    external
    view
    returns (uint24 k, uint24 optimalFeeE6, uint8 targetMultiplier, uint160 referenceSqrtPriceX96);
}

/// @notice The fee configuration getter of the VolatilePairHook.
/// @dev A subset of `IVolatileFeeConfiguration` in Uniswap/v4-hooks-public at commit 82de6aa
/// (`src/volatile/base/VolatileFeeConfiguration.sol`).
interface IVolatilePairHookFeeConfig {
  /// @notice Returns the fee configuration of a pool.
  /// @param poolId The ID of the pool.
  /// @return restingSpreadE6 The permanent spread: the ask fee plus the bid fee, in pips.
  /// @return backrunCaptureFractionE6 The LP share of backrun profit.
  /// @return midFadeRateE6 The continuing-fee growth rate per unit move.
  /// @return maxMidFadeE6 The cap on the continuing fade.
  /// @return skewRateE6 The step of the permanent fee per unit of price impact.
  /// @return maxSkewStepE6 The cap on the step of the permanent fee per block.
  /// @return maxSkewE6 The cap on the permanent fee of either side.
  /// @return backrunThresholdE6 The price impact at which the backrun fee is active.
  /// @return restoreFractionE6 The share of the backrun side's fee decrease that is added back.
  /// @return restoreThresholdE6 The price impact at which the restore fee is active.
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
    );
}
