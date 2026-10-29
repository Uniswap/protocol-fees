// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IV4FeePolicy, IV4ProtocolFeeRuleset} from "./IV4FeePolicy.sol";

/// @title IV4PairHookRuleset
/// @notice A protocol fee ruleset for a dynamic-fee hook. It reads an LP fee from the hook's
/// configuration of the pool, and returns the fee of the hookless curve for that LP fee.
/// @dev The ruleset looks up the hookless curve on POLICY at each call, so a later change of the
/// hookless curve applies to the hook. The ruleset has no configuration of its own.
/// @custom:security-contact security@uniswap.org
interface IV4PairHookRuleset is IV4ProtocolFeeRuleset {
  /// @notice The policy is the zero address.
  error AddressCannotBeZero();

  /// @notice No ruleset is set for hookless pools on the policy.
  error HooklessCurveNotSet();

  /// @notice The policy on which the ruleset looks up the hookless curve.
  function POLICY() external view returns (IV4FeePolicy);

  /// @notice Returns the LP fee that the ruleset uses for a pool, from the hook's configuration.
  /// @param key The key of the pool.
  /// @return The LP fee, in pips.
  function lpFee(PoolKey calldata key) external view returns (uint24);
}
