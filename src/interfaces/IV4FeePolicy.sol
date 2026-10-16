// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";

struct ProtocolFeeRulesetAssignment {
  address hook;
  IV4ProtocolFeeRuleset ruleset;
}

interface IV4ProtocolFeeRuleset {
  /// @notice Returns the protocol fee of a pool.
  /// @param key The key of the pool.
  function getProtocolFee(PoolKey calldata key) external view returns (uint24);
}

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

  /// @notice The call is to the zero address.
  error AddressCannotBeZero();

  /// @notice The caller is not the fee setter.
  error Unauthorized();

  /// @notice Calculates the protocol fee of a pool.
  function computeFee(PoolKey calldata key) external view returns (uint24);

  /// @notice Sets the protocol fee ruleset of a hook. This ruleset applies before a fee from the
  /// hook. Only the fee setter can call this function.
  function setProtocolFeeRuleset(address hook, IV4ProtocolFeeRuleset ruleset) external;

  /// @notice Sets the protocol fee ruleset of each hook in the list. Each ruleset applies before a
  /// fee from the hook. Only the fee setter can call this function.
  function batchSetProtocolFeeRulesets(ProtocolFeeRulesetAssignment[] calldata assignments) external;

  /// @notice Sets the fee setter. Only the owner can call this function.
  /// @param newFeeSetter The new fee setter.
  function setFeeSetter(address newFeeSetter) external;

  /// @notice Sets the default fee. Only the fee setter can call this function.
  /// @param _defaultFee The new default fee.
  function setDefaultFee(uint24 _defaultFee) external;
}
