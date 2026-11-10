// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IV4FeePolicy, IV4ProtocolFeeRuleset} from "./IV4FeePolicy.sol";

/// @title IV4PairHookRuleset
/// @notice A protocol fee ruleset for a dynamic-fee hook. It reads an LP fee from the hook's
/// configuration of the pool, and returns the fee that the policy gives a hookless pool with the
/// same currencies, the same tick spacing and that LP fee. Thus the hook's pools follow the same
/// rules as hookless pools.
/// @dev The ruleset asks the policy at each call, so a later change of the rules for hookless
/// pools applies to the hook. The ruleset has no configuration of its own. Do not set it as the
/// ruleset of hookless pools: it would call itself until it runs out of gas.
/// @custom:security-contact security@uniswap.org
interface IV4PairHookRuleset is IV4ProtocolFeeRuleset {
  /// @notice The policy is the zero address.
  error AddressCannotBeZero();

  /// @notice The policy that gives the fee of hookless pools.
  function POLICY() external view returns (IV4FeePolicy);

  /// @notice Returns the LP fee that the ruleset uses for a pool, from the hook's configuration.
  /// @param key The key of the pool.
  /// @return The LP fee, in pips.
  function lpFee(PoolKey calldata key) external view returns (uint24);
}
