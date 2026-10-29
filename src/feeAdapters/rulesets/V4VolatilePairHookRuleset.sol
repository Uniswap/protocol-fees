// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IV4FeePolicy} from "../../interfaces/IV4FeePolicy.sol";
import {IVolatilePairHookFeeConfig} from "../../interfaces/external/IPairHookFeeConfig.sol";
import {V4PairHookRuleset} from "./V4PairHookRuleset.sol";

/// @title V4VolatilePairHookRuleset
/// @notice A protocol fee ruleset for the VolatilePairHook. The LP fee is half of the resting
/// spread of the pool, `restingSpreadE6 / 2`, rounded down.
/// @dev The resting spread is the ask fee plus the bid fee, thus half of it is the fee in one
/// direction. The hook sets each side to that value when the configuration changes. The fee of a
/// VolatilePairHook pool changes in each block. The resting spread is fixed per pool, so the time
/// at which a caller triggers the fee update does not change the protocol fee.
/// @custom:security-contact security@uniswap.org
contract V4VolatilePairHookRuleset is V4PairHookRuleset {
  using PoolIdLibrary for PoolKey;

  /// @param policy The policy on which the ruleset looks up the hookless curve.
  constructor(IV4FeePolicy policy) V4PairHookRuleset(policy) {}

  /// @dev Returns half of the resting spread of the pool, rounded down.
  function _lpFee(PoolKey calldata key) internal view override returns (uint24) {
    (uint24 restingSpreadE6,,,,,,,,,) =
      IVolatilePairHookFeeConfig(address(key.hooks)).feeConfig(key.toId());
    return restingSpreadE6 / 2;
  }
}
