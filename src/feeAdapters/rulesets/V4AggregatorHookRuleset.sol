// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {IV4ProtocolFeeRuleset} from "../../interfaces/IV4FeePolicy.sol";
import {IV4AggregatorHookRuleset} from "../../interfaces/IV4AggregatorHookRuleset.sol";

/// @title V4AggregatorHookRuleset
/// @notice A protocol fee ruleset for aggregator hooks. A pair of two stablecoins pays the stable
/// pair fee. All other pairs pay the volatile pair fee.
/// @dev The configuration is set at deployment and cannot change, so the ruleset has no owner.
/// @custom:security-contact security@uniswap.org
contract V4AggregatorHookRuleset is IV4AggregatorHookRuleset {
  /// @inheritdoc IV4AggregatorHookRuleset
  uint24 public immutable HOOK_FEE_MULTIPLIER;

  /// @inheritdoc IV4AggregatorHookRuleset
  uint24 public immutable VOLATILE_PAIR_FEE;

  /// @inheritdoc IV4AggregatorHookRuleset
  uint24 public immutable STABLE_PAIR_FEE;

  /// @dev The packed protocol fee for a volatile pair: VOLATILE_PAIR_FEE / HOOK_FEE_MULTIPLIER.
  uint24 internal immutable VOLATILE_PAIR_PROTOCOL_FEE;

  /// @dev The packed protocol fee for a stable pair: STABLE_PAIR_FEE / HOOK_FEE_MULTIPLIER.
  uint24 internal immutable STABLE_PAIR_PROTOCOL_FEE;

  /// @inheritdoc IV4AggregatorHookRuleset
  mapping(Currency currency => bool) public isStablecoin;

  /// @inheritdoc IV4AggregatorHookRuleset
  Currency[] public stablecoins;

  /// @param volatilePairFee The fee that the hook charges in each direction on a pair that is not
  /// two stablecoins, in pips, after the multiplier.
  /// @param stablePairFee The fee that the hook charges in each direction on a pair of two
  /// stablecoins, in pips, after the multiplier.
  /// @param hookFeeMultiplier The multiplier that the aggregator hooks apply to the protocol fee.
  /// @param _stablecoins The stablecoins on this chain.
  constructor(
    uint24 volatilePairFee,
    uint24 stablePairFee,
    uint24 hookFeeMultiplier,
    Currency[] memory _stablecoins
  ) {
    if (hookFeeMultiplier == 0) revert ZeroMultiplier();
    HOOK_FEE_MULTIPLIER = hookFeeMultiplier;
    VOLATILE_PAIR_FEE = volatilePairFee;
    STABLE_PAIR_FEE = stablePairFee;
    VOLATILE_PAIR_PROTOCOL_FEE = _toProtocolFee(volatilePairFee, hookFeeMultiplier);
    STABLE_PAIR_PROTOCOL_FEE = _toProtocolFee(stablePairFee, hookFeeMultiplier);

    uint256 len = _stablecoins.length;
    for (uint256 i; i < len; ++i) {
      Currency stablecoin = _stablecoins[i];
      if (stablecoin.isAddressZero()) revert NativeCurrencyNotStablecoin();
      if (isStablecoin[stablecoin]) revert DuplicateStablecoin(stablecoin);
      isStablecoin[stablecoin] = true;
      stablecoins.push(stablecoin);
    }
  }

  /// @inheritdoc IV4ProtocolFeeRuleset
  function getProtocolFee(PoolKey calldata key) external view returns (uint24) {
    if (isStablecoin[key.currency0] && isStablecoin[key.currency1]) {
      return STABLE_PAIR_PROTOCOL_FEE;
    }
    return VOLATILE_PAIR_PROTOCOL_FEE;
  }

  /// @inheritdoc IV4AggregatorHookRuleset
  function stablecoinsLength() external view returns (uint256) {
    return stablecoins.length;
  }

  /// @dev Returns the packed protocol fee that the hook multiplies into `fee`. Reverts if the hook
  /// could not charge `fee` exactly, or if the protocol fee is more than MAX_PROTOCOL_FEE.
  function _toProtocolFee(uint24 fee, uint24 multiplier) private pure returns (uint24) {
    if (fee % multiplier != 0) revert FeeNotDivisibleByMultiplier(fee, multiplier);
    uint24 perDirection = fee / multiplier;
    if (perDirection > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) revert InvalidFeeValue(fee);
    return (perDirection << 12) | perDirection;
  }
}
