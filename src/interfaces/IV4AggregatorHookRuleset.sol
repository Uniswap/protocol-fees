// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "v4-core/types/Currency.sol";
import {IV4ProtocolFeeRuleset} from "./IV4FeePolicy.sol";

/// @dev The key at which governance can register the aggregator hook ruleset on V4FeePolicy. An
/// aggregator hook that opts in can look up the ruleset at this key and forward `getProtocolFee`
/// to it, so a later change of the ruleset applies to the hook. Hooks that do not forward are
/// assigned the ruleset by address.
address constant AGGREGATOR_HOOK_RULESET_KEY = address(uint160(uint256(keccak256("AGGREGATOR"))));

/// @title IV4AggregatorHookRuleset
/// @notice A protocol fee ruleset for aggregator hooks. A stable pair pays the stable pair fee.
/// All other pairs pay the volatile pair fee.
/// @dev At deployment, each currency that has a like-for-like value gets an ID. Currencies with
/// the same ID have the same value, thus a pair of two currencies with the same ID is a stable
/// pair. For example, `bytes32("USD")` can identify tokens with the value of one USD, and
/// `bytes32("BTC")` can identify tokens of BTC. Each currency has a maximum of one ID. A currency
/// without an ID (zero) is not in a stable pair.
/// An aggregator hook multiplies the protocol fee of its pool by its `protocolFeeMultiplier`, and
/// charges the result on the swap. The ruleset reads the multiplier from each hook and returns the
/// fee divided by it, rounded down, so the hook charges at most the fee. The fees and the IDs
/// are set at deployment and cannot change. To change them, deploy a new ruleset and set it on the
/// policy. If the multiplier is more than a fee that is not zero, that fee rounds down to zero,
/// thus the ruleset reverts.
/// @custom:security-contact security@uniswap.org
interface IV4AggregatorHookRuleset is IV4ProtocolFeeRuleset {
  /// @notice A currency and its ID. Currencies with the same ID have the same value.
  /// @param currency The currency.
  /// @param id The ID of the value of the currency, for example `bytes32("USD")`. It cannot be
  /// zero.
  struct CurrencyId {
    Currency currency;
    bytes32 id;
  }

  /// @notice An ID is zero.
  /// @param currency The currency with the zero ID.
  error ZeroId(Currency currency);

  /// @notice A currency is in the list more than once.
  /// @param currency The currency.
  error DuplicateCurrency(Currency currency);

  /// @notice The protocol fee multiplier of the hook is zero.
  /// @param hook The hook.
  error ZeroMultiplier(address hook);

  /// @notice The protocol fee multiplier of the hook is more than the fee, which is not zero. The
  /// fee divided by the multiplier rounds down to zero.
  /// @param hook The hook.
  /// @param multiplier The protocol fee multiplier of the hook.
  /// @param fee The fee of the pair, in pips.
  error MultiplierAboveFee(address hook, uint24 multiplier, uint24 fee);

  /// @notice The target fee that the hook charges in each direction on a pair that is not a stable
  /// pair, in pips, after the multiplier has been applied. The ruleset divides it by the
  /// multiplier, rounded down, to a maximum of MAX_PROTOCOL_FEE. Thus the hook can charge less.
  /// @return The volatile pair fee, in pips.
  function VOLATILE_PAIR_FEE() external view returns (uint24);

  /// @notice The target fee that the hook charges in each direction on a stable pair, in pips,
  /// after the multiplier has been applied. The ruleset divides it by the multiplier, rounded
  /// down, to a maximum of MAX_PROTOCOL_FEE. Thus the hook can charge less.
  /// @return The stable pair fee, in pips.
  function STABLE_PAIR_FEE() external view returns (uint24);

  /// @notice Returns the ID of a currency. Two currencies with the same ID that is not zero are a
  /// stable pair.
  /// @param currency The currency.
  /// @return The ID of the currency, or zero if the currency has no ID.
  function id(Currency currency) external view returns (bytes32);

  /// @notice Returns true if the two currencies are a stable pair. The order of the currencies
  /// has no effect.
  /// @param currencyA A currency of the pair.
  /// @param currencyB The other currency of the pair.
  /// @return True if the two currencies have the same ID, and that ID is not zero.
  function isStablePair(Currency currencyA, Currency currencyB) external view returns (bool);
}
