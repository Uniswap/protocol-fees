// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IV4FeePolicy} from "../../interfaces/IV4FeePolicy.sol";
import {IStablePairHookFeeConfig} from "../../interfaces/external/IPairHookFeeConfig.sol";
import {V4PairHookRuleset} from "./V4PairHookRuleset.sol";

/// @title V4StablePairHookRuleset
/// @notice A protocol fee ruleset for the StablePairHook. The LP fee is the optimal fee of the
/// pool, `optimalFeeE6`.
/// @dev The fee of a StablePairHook pool changes in each block. The optimal fee is fixed per pool,
/// so the time at which a caller triggers the fee update does not change the protocol fee.
/// @custom:security-contact security@uniswap.org
contract V4StablePairHookRuleset is V4PairHookRuleset {
  using PoolIdLibrary for PoolKey;

  /// @param policy The policy on which the ruleset looks up the hookless curve.
  constructor(IV4FeePolicy policy) V4PairHookRuleset(policy) {}

  /// @dev Returns the optimal fee of the pool.
  function _lpFee(PoolKey calldata key) internal view override returns (uint24 optimalFeeE6) {
    (, optimalFeeE6,,) = IStablePairHookFeeConfig(address(key.hooks)).feeConfig(key.toId());
  }
}
