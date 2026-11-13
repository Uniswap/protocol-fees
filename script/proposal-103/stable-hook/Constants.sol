// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {StableFeeConfig} from "./Interfaces.sol";

// -------------------------------------------------------------------------------------------------
// StablePairHook fee config parameters

/// @dev A pool the update changes, and its `optimalFeeE6` before the update.
struct StablePool {
  bytes32 id;
  uint24 currentOptimalFeeE6;
}

/// @dev Arbitrum parameters of the StablePairHook fee config update.
library StableHook {
  /// @dev The hook's ERC1967 proxy, the registered v4 hook.
  ///      https://arbiscan.io/address/0x630e9cac0fff557bd3a01daa111ed253c771bcc0
  address constant PROXY = 0x630e9CaC0ffF557Bd3A01DAa111ed253c771Bcc0;

  /// @dev The USDG/USDC pool with tick spacing 1 and a dynamic fee: the id of the pool key
  ///      (0x004B506865409877C9fA29bfb1ebA929984B9bbC, 0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
  ///      0x800000, 1, PROXY).
  bytes32 constant TICK_SPACING_1_POOL_ID =
    0x52b42d5f1e4a0d4bce86667bb069cf257e512d98ce617f549f6e4fbb0bee41e6;

  /// @dev The USDG/USDC pool with tick spacing 2 and a dynamic fee: the id of the pool key
  ///      (0x004B506865409877C9fA29bfb1ebA929984B9bbC, 0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
  ///      0x800000, 2, PROXY).
  bytes32 constant TICK_SPACING_2_POOL_ID =
    0xa3f30a5e5c37d1119a6f6149a16827c181efe513938c5dea88213d00f14c4e51;

  /// @dev Each pool's `optimalFeeE6` after the update.
  uint24 constant NEW_OPTIMAL_FEE_E6 = 7;

  /// @dev Each pool's `k`, unchanged by the update.
  uint24 constant K = 16_653_011;

  /// @dev Each pool's `targetMultiplier`, unchanged by the update.
  uint8 constant TARGET_MULTIPLIER = 100;

  /// @dev Each pool's `referenceSqrtPriceX96`, unchanged by the update: a price of 1.
  uint160 constant REFERENCE_SQRT_PRICE_X96 = 2 ** 96;

  /// @dev Returns the pools the update changes, with their `optimalFeeE6` before the update.
  function pools() internal pure returns (StablePool[] memory pools_) {
    pools_ = new StablePool[](2);
    pools_[0] = StablePool({id: TICK_SPACING_1_POOL_ID, currentOptimalFeeE6: 50});
    pools_[1] = StablePool({id: TICK_SPACING_2_POOL_ID, currentOptimalFeeE6: 8});
  }

  /// @dev Returns a pool's fee config with `optimalFeeE6` set to `optimalFeeE6`.
  function feeConfig(uint24 optimalFeeE6) internal pure returns (StableFeeConfig memory) {
    return StableFeeConfig({
      k: K,
      optimalFeeE6: optimalFeeE6,
      targetMultiplier: TARGET_MULTIPLIER,
      referenceSqrtPriceX96: REFERENCE_SQRT_PRICE_X96
    });
  }
}
