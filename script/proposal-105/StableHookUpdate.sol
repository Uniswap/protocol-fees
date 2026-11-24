// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Uniswap} from "govkit/types/Uniswap.sol";
import {Call} from "govkit/types/Call.sol";
import {InboxEncoder} from "govkit/bridges/InboxEncoder.sol";

import {IStablePairHook, StableFeeConfig} from "./Interfaces.sol";
import {StableHook, StablePool} from "./params/StableHook.sol";

/// @notice Returns the call that sets the `optimalFeeE6` of Arbitrum's StablePairHook pools: one
///         retryable ticket from the Timelock through Arbitrum's Inbox, which Arbitrum runs from
///         the Timelock's alias.
/// @dev The ticket uses govkit's default gas limit and fees. The hook replaces each pool's whole
///      fee config, so each new config carries the pool's other three fields unchanged.
function buildUpdateStableHookFeeConfigCall(Uniswap storage uniswap) view returns (Call memory) {
  StablePool[] memory pools = StableHook.pools();
  bytes32[] memory poolIds = new bytes32[](pools.length);
  StableFeeConfig[] memory feeConfigs = new StableFeeConfig[](pools.length);
  for (uint256 i; i < pools.length; i++) {
    poolIds[i] = pools[i].id;
    feeConfigs[i] = StableHook.feeConfig(StableHook.NEW_OPTIMAL_FEE_E6);
  }

  return InboxEncoder.encode({
    inbox: uniswap.ethereum.bridge.arbitrum,
    timelock: uniswap.ethereum.timelock,
    remoteCall: Call({
      target: StableHook.PROXY,
      value: 0,
      data: abi.encodeCall(IStablePairHook.batchUpdateFeeConfig, (poolIds, feeConfigs))
    })
  });
}

/// @notice Asserts on Arbitrum that the Timelock's alias can update the hook's fee configs, and
///         that each pool's fee config is the one the update replaces, so the update changes only
///         `optimalFeeE6`.
function checkStableHookBefore(Uniswap storage uniswap) view {
  IStablePairHook hook = IStablePairHook(StableHook.PROXY);
  require(
    hook.hasRole(hook.CONFIG_MANAGER_ROLE(), InboxEncoder.arbitrumAlias(uniswap.ethereum.timelock)),
    "stableHook.aliasedTimelockIsConfigManager"
  );

  StablePool[] memory pools = StableHook.pools();
  for (uint256 i; i < pools.length; i++) {
    _checkFeeConfig(pools[i].id, StableHook.feeConfig(pools[i].currentOptimalFeeE6));
  }
}

/// @notice Asserts on Arbitrum that each pool's fee config carries the new `optimalFeeE6`.
function checkStableHookAfter() view {
  StablePool[] memory pools = StableHook.pools();
  for (uint256 i; i < pools.length; i++) {
    _checkFeeConfig(pools[i].id, StableHook.feeConfig(StableHook.NEW_OPTIMAL_FEE_E6));
  }
}

/// @dev Asserts that the fee config of the pool `poolId` equals `expected`.
function _checkFeeConfig(bytes32 poolId, StableFeeConfig memory expected) view {
  (uint24 k, uint24 optimalFeeE6, uint8 targetMultiplier, uint160 referenceSqrtPriceX96) =
    IStablePairHook(StableHook.PROXY).feeConfig(poolId);
  require(k == expected.k, "stableHook.feeConfig.k");
  require(optimalFeeE6 == expected.optimalFeeE6, "stableHook.feeConfig.optimalFeeE6");
  require(targetMultiplier == expected.targetMultiplier, "stableHook.feeConfig.targetMultiplier");
  require(
    referenceSqrtPriceX96 == expected.referenceSqrtPriceX96,
    "stableHook.feeConfig.referenceSqrtPriceX96"
  );
}
