// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {IV4ProtocolFeeRuleset} from "../../interfaces/IV4FeePolicy.sol";
import {IV4AggregatorHookRuleset} from "../../interfaces/IV4AggregatorHookRuleset.sol";
import {
  IAggregatorHookProtocolFees
} from "../../interfaces/external/IAggregatorHookProtocolFees.sol";

/// @title V4AggregatorHookRuleset
/// @notice A protocol fee ruleset for aggregator hooks. A pair of two stablecoins pays the stable
/// pair fee. All other pairs pay the volatile pair fee.
/// @dev The configuration is set at deployment and cannot change, so the ruleset has no owner.
/// @custom:security-contact security@uniswap.org
contract V4AggregatorHookRuleset is IV4AggregatorHookRuleset {
  /// @inheritdoc IV4AggregatorHookRuleset
  uint24 public immutable VOLATILE_PAIR_FEE;

  /// @inheritdoc IV4AggregatorHookRuleset
  uint24 public immutable STABLE_PAIR_FEE;

  /// @inheritdoc IV4AggregatorHookRuleset
  mapping(Currency currency => bool) public isStablecoin;

  /// @param volatilePairFee The actual fee that the hook charges in each direction on a pair that
  /// is not two stablecoins, in pips, after the multiplier has been applied.
  /// @param stablePairFee The actual fee that the hook charges in each direction on a pair of two
  /// stablecoins, in pips, after the multiplier has been applied.
  /// @param stablecoins The stablecoins on this chain.
  constructor(uint24 volatilePairFee, uint24 stablePairFee, Currency[] memory stablecoins) {
    VOLATILE_PAIR_FEE = volatilePairFee;
    STABLE_PAIR_FEE = stablePairFee;

    uint256 len = stablecoins.length;
    for (uint256 i; i < len; ++i) {
      Currency stablecoin = stablecoins[i];
      if (stablecoin.isAddressZero()) revert NativeCurrencyNotStablecoin();
      if (isStablecoin[stablecoin]) revert DuplicateStablecoin(stablecoin);
      isStablecoin[stablecoin] = true;
    }
  }

  /// @inheritdoc IV4ProtocolFeeRuleset
  /// @dev Returns the fee divided by the hook's multiplier, rounded down, in each direction. If
  /// that is more than MAX_PROTOCOL_FEE, returns MAX_PROTOCOL_FEE. Reverts if the multiplier is
  /// zero.
  function getProtocolFee(PoolKey calldata key) external view returns (uint24) {
    uint24 fee = isStablecoin[key.currency0] && isStablecoin[key.currency1]
      ? STABLE_PAIR_FEE
      : VOLATILE_PAIR_FEE;

    uint24 multiplier = IAggregatorHookProtocolFees(address(key.hooks)).protocolFeeMultiplier();
    if (multiplier == 0) revert ZeroMultiplier(address(key.hooks));

    uint24 perDirection = fee / multiplier;
    if (perDirection > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) {
      perDirection = ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
    }
    return (perDirection << 12) | perDirection;
  }
}
