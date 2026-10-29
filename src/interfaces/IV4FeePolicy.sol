// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";

struct ProtocolFeeRulesetAssignment {
  address hook;
  IV4ProtocolFeeRuleset ruleset;
}

interface IV4ProtocolFeeRuleset {
  /// @notice Allows a ruleset to return the protocol fee for a given pool.
  /// @param key The pool key to return the protocol fee for.
  function getProtocolFee(PoolKey calldata key) external view returns (uint24);
}

interface IV4FeePolicy {
  /// @notice Emitted when a protocol fee ruleset is set for a given hook.
  /// @param hook The hook that the ruleset is set for.
  /// @param ruleset The ruleset that is set.
  event ProtocolFeeRulesetChanged(address indexed hook, IV4ProtocolFeeRuleset ruleset);

  /// @notice Emitted when the default fee is updated.
  /// @param oldDefaultFee The old default fee.
  /// @param newDefaultFee The new default fee.
  event DefaultFeeUpdated(uint24 oldDefaultFee, uint24 newDefaultFee);

  /// @notice Emitted when the fee setter address is updated.
  /// @param oldFeeSetter The old fee setter address.
  /// @param newFeeSetter The new fee setter address.
  event FeeSetterUpdated(address oldFeeSetter, address newFeeSetter);

  /// @notice Thrown when a fee value fails ProtocolFeeLibrary.isValidProtocolFee.
  error InvalidFeeValue();

  /// @notice Thrown when making a call to the zero address.
  error AddressCannotBeZero();

  /// @notice Thrown when an unauthorized address calls a restricted function.
  error Unauthorized();

  /// @notice Compute the protocol fee for a given pool.
  function computeFee(PoolKey calldata key) external view returns (uint24);

  /// @notice Explictly set a protocol fee ruleset for a given hook. This overrides
  ///         any reported by the hook itself.
  function setProtocolFeeRuleset(address hook, IV4ProtocolFeeRuleset ruleset) external;

  /// @notice Explictly set a protocol fee ruleset for a given hook. This overrides
  ///         any reported by the hook itself.
  function batchSetProtocolFeeRulesets(ProtocolFeeRulesetAssignment[] calldata assignments) external;

  /// @notice Sets the fee setter address. Only callable by owner.
  /// @param newFeeSetter The new fee setter address.
  function setFeeSetter(address newFeeSetter) external;

  /// @notice Sets the default fee. Only callable by the fee setter.
  /// @param _defaultFee The new default fee.
  function setDefaultFee(uint24 _defaultFee) external;
}
