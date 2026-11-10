// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IV4ProtocolFeeRuleset} from "./IV4FeePolicy.sol";

/// @title IV4PairHookRuleset
/// @notice A protocol fee ruleset for a dynamic-fee hook. It reads an LP fee from the hook's
/// configuration of the pool, and returns the fee that the caller (the policy) gives a hookless
/// pool with the same currencies, the same tick spacing and that LP fee. Thus the hook's pools
/// follow the same rules as hookless pools.
/// @dev The ruleset asks the caller at each call, so a later change of the rules for hookless
/// pools applies to the hook. The ruleset has no configuration of its own, thus different policies
/// can use the same ruleset. A call to `getProtocolFee` from an account that is not a policy
/// reverts. Do not set it as the ruleset of hookless pools: it would call itself until it runs out
/// of gas.
/// @custom:security-contact security@uniswap.org
interface IV4PairHookRuleset is IV4ProtocolFeeRuleset {
  /// @notice Returns the LP fee that the ruleset uses for a pool, from the hook's configuration.
  /// @param key The key of the pool.
  /// @return The LP fee, in pips.
  function lpFee(PoolKey calldata key) external view returns (uint24);
}
