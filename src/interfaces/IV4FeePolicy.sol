// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";

/// @dev One assignment of a protocol fee ruleset to a hook, for `batchSetProtocolFeeRulesets`.
struct ProtocolFeeRulesetAssignment {
  /// @dev The hook address, or a sentinel key. `address(0)` is the key of hookless pools.
  address hook;
  /// @dev The ruleset of the hook. The zero address removes the ruleset of the hook.
  IV4ProtocolFeeRuleset ruleset;
}

/// @title IV4ProtocolFeeRuleset
/// @notice A set of rules that gives the protocol fee of a pool. V4FeePolicy calls a ruleset to
/// get the fee of a pool.
/// @custom:security-contact security@uniswap.org
interface IV4ProtocolFeeRuleset {
  /// @notice Returns the protocol fee of a pool.
  /// @param key The key of the pool.
  /// @return The protocol fee, in pips. The lower 12 bits are the fee of a zeroForOne swap, and
  /// the upper 12 bits are the fee of a oneForZero swap.
  function getProtocolFee(PoolKey calldata key) external view returns (uint24);
}

/// @title IV4FeePolicy
/// @notice The policy that gives the protocol fee of a Uniswap v4 pool to V4FeeAdapter. The fee
/// comes from the protocol fee ruleset of the hook of the pool, or from the default fee.
/// @custom:security-contact security@uniswap.org
interface IV4FeePolicy {
  /// @notice The fee setter sets a protocol fee ruleset for a hook.
  /// @param hook The hook.
  /// @param ruleset The ruleset.
  event ProtocolFeeRulesetChanged(address indexed hook, IV4ProtocolFeeRuleset ruleset);

  /// @notice The fee setter changes the default fee.
  /// @param oldDefaultFee The previous default fee.
  /// @param newDefaultFee The new default fee.
  event DefaultFeeUpdated(uint24 oldDefaultFee, uint24 newDefaultFee);

  /// @notice The owner changes the fee setter.
  /// @param oldFeeSetter The previous fee setter.
  /// @param newFeeSetter The new fee setter.
  event FeeSetterUpdated(address oldFeeSetter, address newFeeSetter);

  /// @notice The fee is above MAX_PROTOCOL_FEE.
  error InvalidFeeValue();

  /// @notice An address is the zero address, but the zero address is not permitted.
  error AddressCannotBeZero();

  /// @notice The caller is not the fee setter.
  error Unauthorized();

  /// @notice Calculates the protocol fee of a pool.
  /// @param key The key of the pool.
  /// @return The protocol fee, in pips. The lower 12 bits are the fee of a zeroForOne swap, and
  /// the upper 12 bits are the fee of a oneForZero swap.
  function computeFee(PoolKey calldata key) external view returns (uint24);

  /// @notice Returns the ruleset set for a hook. `address(0)` is the key of hookless pools.
  /// @param hook The hook address, or a sentinel key.
  /// @return The ruleset of the hook, or the zero address if the hook has no ruleset.
  function rulesets(address hook) external view returns (IV4ProtocolFeeRuleset);

  /// @notice Sets the protocol fee ruleset of a hook. This ruleset applies before a fee from the
  /// hook. Only the fee setter can call this function.
  /// @param hook The hook address, or a sentinel key. `address(0)` is the key of hookless pools.
  /// @param ruleset The ruleset of the hook. The zero address removes the ruleset of the hook.
  function setProtocolFeeRuleset(address hook, IV4ProtocolFeeRuleset ruleset) external;

  /// @notice Sets the protocol fee ruleset of each hook in the list. Each ruleset applies before a
  /// fee from the hook. Only the fee setter can call this function.
  /// @param assignments The hooks and their rulesets, applied in the sequence of the list.
  function batchSetProtocolFeeRulesets(ProtocolFeeRulesetAssignment[] calldata assignments) external;

  /// @notice Sets the fee setter. Only the owner can call this function.
  /// @param newFeeSetter The new fee setter. It cannot be the zero address.
  function setFeeSetter(address newFeeSetter) external;

  /// @notice Sets the default fee. Only the fee setter can call this function.
  /// @param _defaultFee The new default fee.
  function setDefaultFee(uint24 _defaultFee) external;
}
