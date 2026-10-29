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
/// @notice A protocol fee ruleset for aggregator hooks. A pair of two stablecoins pays the stable
/// pair fee. All other pairs pay the volatile pair fee.
/// @dev An aggregator hook multiplies the protocol fee of its pool by a fixed multiplier, and
/// charges the result on the swap. Thus, this ruleset returns each fee divided by that multiplier.
/// The fees, the multiplier and the stablecoins are set at deployment and cannot change. To
/// change them, deploy a new ruleset and set it on the policy.
/// @custom:security-contact security@uniswap.org
interface IV4AggregatorHookRuleset is IV4ProtocolFeeRuleset {
  /// @notice The multiplier is zero.
  error ZeroMultiplier();

  /// @notice A fee is not a multiple of the multiplier, thus the hook could not charge it exactly.
  /// @param fee The fee, in pips.
  /// @param multiplier The multiplier of the hooks.
  error FeeNotDivisibleByMultiplier(uint24 fee, uint24 multiplier);

  /// @notice A fee divided by the multiplier is more than MAX_PROTOCOL_FEE.
  /// @param fee The fee, in pips.
  error InvalidFeeValue(uint24 fee);

  /// @notice A stablecoin is the native currency.
  error NativeCurrencyNotStablecoin();

  /// @notice A stablecoin is in the list more than once.
  /// @param stablecoin The stablecoin.
  error DuplicateStablecoin(Currency stablecoin);

  /// @notice The multiplier that the aggregator hooks apply to the protocol fee of their pools.
  function HOOK_FEE_MULTIPLIER() external view returns (uint24);

  /// @notice The fee that the hook charges in each direction on a pair that is not two
  /// stablecoins, in pips, after the multiplier.
  function VOLATILE_PAIR_FEE() external view returns (uint24);

  /// @notice The fee that the hook charges in each direction on a pair of two stablecoins, in
  /// pips, after the multiplier.
  function STABLE_PAIR_FEE() external view returns (uint24);

  /// @notice Returns true if the currency is a stablecoin.
  /// @param currency The currency.
  function isStablecoin(Currency currency) external view returns (bool);

  /// @notice Returns the stablecoin at an index.
  /// @param index The index of the stablecoin.
  function stablecoins(uint256 index) external view returns (Currency);

  /// @notice Returns the number of stablecoins.
  function stablecoinsLength() external view returns (uint256);
}
