// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IStablePairHookFeeConfig} from "../../interfaces/external/IPairHookFeeConfig.sol";
import {V4PairHookRuleset} from "./V4PairHookRuleset.sol";

/// @title V4StablePairHookRuleset
/// @notice A protocol fee ruleset for the StablePairHook. The LP fee is the optimal fee of the
/// pool, `optimalFeeE6`.
/// @dev The fee of a StablePairHook pool changes in each block. The ruleset reads the optimal fee
/// from the hook at each call. The optimal fee changes only when the hook's configuration of the
/// pool changes. Thus, between configuration changes, the time at which a caller triggers the fee
/// update does not change the protocol fee.
/// @custom:security-contact security@uniswap.org
contract V4StablePairHookRuleset is V4PairHookRuleset {
  using PoolIdLibrary for PoolKey;

  /// @dev Returns the optimal fee of the pool.
  /// @param key The key of the pool.
  /// @return The optimal fee of the pool, in pips.
  function _lpFee(PoolKey calldata key) internal view override returns (uint24) {
    (, uint24 optimalFeeE6,,) = IStablePairHookFeeConfig(address(key.hooks)).feeConfig(key.toId());
    return optimalFeeE6;
  }
}
