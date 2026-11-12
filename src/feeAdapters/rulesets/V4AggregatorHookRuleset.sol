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
/// @notice A protocol fee ruleset for aggregator hooks. A stable pair pays the stable pair fee.
/// All other pairs pay the volatile pair fee.
/// @dev The configuration is set at deployment and cannot change, so the ruleset has no owner.
/// @custom:security-contact security@uniswap.org
contract V4AggregatorHookRuleset is IV4AggregatorHookRuleset {
  /// @inheritdoc IV4AggregatorHookRuleset
  uint24 public immutable VOLATILE_PAIR_FEE;

  /// @inheritdoc IV4AggregatorHookRuleset
  uint24 public immutable STABLE_PAIR_FEE;

  /// @inheritdoc IV4AggregatorHookRuleset
  mapping(Currency currency => bytes32) public id;

  /// @param volatilePairFee The actual fee that the hook charges in each direction on a pair that
  /// is not a stable pair, in pips, after the multiplier has been applied.
  /// @param stablePairFee The actual fee that the hook charges in each direction on a stable pair,
  /// in pips, after the multiplier has been applied.
  /// @param ids The currencies on this chain that have an ID, and their IDs. Currencies with the
  /// same ID are stable pairs. A currency can be the native currency.
  constructor(uint24 volatilePairFee, uint24 stablePairFee, CurrencyId[] memory ids) {
    VOLATILE_PAIR_FEE = volatilePairFee;
    STABLE_PAIR_FEE = stablePairFee;

    uint256 len = ids.length;
    for (uint256 i; i < len; ++i) {
      CurrencyId memory entry = ids[i];
      if (entry.id == bytes32(0)) revert ZeroId(entry.currency);
      if (id[entry.currency] != bytes32(0)) revert DuplicateCurrency(entry.currency);
      id[entry.currency] = entry.id;
    }
  }

  /// @inheritdoc IV4AggregatorHookRuleset
  function isStablePair(Currency currencyA, Currency currencyB) public view returns (bool) {
    bytes32 idA = id[currencyA];
    return idA != bytes32(0) && idA == id[currencyB];
  }

  /// @inheritdoc IV4ProtocolFeeRuleset
  /// @dev Returns the fee divided by the hook's multiplier, rounded down, in each direction. If
  /// that is more than MAX_PROTOCOL_FEE, returns MAX_PROTOCOL_FEE. Reverts if the multiplier is
  /// zero.
  function getProtocolFee(PoolKey calldata key) external view returns (uint24) {
    uint24 fee = isStablePair(key.currency0, key.currency1) ? STABLE_PAIR_FEE : VOLATILE_PAIR_FEE;

    uint24 multiplier = IAggregatorHookProtocolFees(address(key.hooks)).protocolFeeMultiplier();
    if (multiplier == 0) revert ZeroMultiplier(address(key.hooks));

    uint24 perDirection = fee / multiplier;
    if (perDirection > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) {
      perDirection = ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
    }
    return (perDirection << 12) | perDirection;
  }
}
