// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";

/// @title IV4FeeAdapter
/// @notice Interface for the Uniswap V4 protocol fee controller with tiered fee resolution
/// @dev Resolves fees using a waterfall pattern: pool override → fee tier → default
interface IV4FeeAdapter {
  /// @notice Thrown when an unauthorized address attempts to call a restricted function
  error Unauthorized();

  /// @notice Thrown when the provided protocol fee exceeds the maximum allowed
  error ProtocolFeeTooLarge(uint24 fee);

  /// @notice Emitted when the default protocol fee is updated
  /// @param newFee The new default fee value
  event DefaultFeeUpdated(uint24 newFee);

  /// @notice Emitted when a fee tier override is updated
  /// @param lpFee The LP fee tier that was updated
  /// @param protocolFee The new protocol fee for this tier
  event FeeTierOverrideUpdated(uint24 indexed lpFee, uint24 protocolFee);

  /// @notice Emitted when a pool-specific override is updated
  /// @param poolId The pool ID that was updated
  /// @param protocolFee The new protocol fee for this pool
  event PoolOverrideUpdated(PoolId indexed poolId, uint24 protocolFee);

  /// @notice Emitted when the fee setter address is updated
  /// @param newFeeSetter The new fee setter address
  event FeeSetterUpdated(address indexed newFeeSetter);

  /// @notice The Uniswap V4 PoolManager contract
  function POOL_MANAGER() external view returns (IPoolManager);

  /// @notice The address where collected fees are sent
  function TOKEN_JAR() external view returns (address);

  /// @notice Sentinel value stored to represent an explicit zero fee (disabled)
  /// @dev In storage: 0 = "not set", ZERO_FEE_SENTINEL = "explicitly zero", other = actual fee
  function ZERO_FEE_SENTINEL() external pure returns (uint24);

  /// @notice The default protocol fee applied when no overrides match
  function defaultFee() external view returns (uint24);

  /// @notice Returns the fee tier override for a given LP fee (raw storage value)
  /// @param lpFee The LP fee tier to query
  /// @return protocolFee The stored value (0 = not set, ZERO_FEE_SENTINEL = zero fee, other = actual fee)
  function feeTierOverrides(uint24 lpFee) external view returns (uint24 protocolFee);

  /// @notice Returns the pool-specific override for a given pool (raw storage value)
  /// @param poolId The pool ID to query
  /// @return protocolFee The stored value (0 = not set, ZERO_FEE_SENTINEL = zero fee, other = actual fee)
  function poolOverrides(PoolId poolId) external view returns (uint24 protocolFee);

  /// @notice The authorized address to set fee values
  function feeSetter() external view returns (address);

  /// @notice Resolves the protocol fee for a pool using the waterfall pattern
  /// @dev Returns a packed fee for BOTH swap directions (symmetric).
  ///      V4 protocol fee format: lower 12 bits = zeroForOne, upper 12 bits = oneForZero.
  ///      Example: 500 pips stored → returns (500 << 12) | 500 = 2048500
  /// @param key The pool key to resolve fees for
  /// @return fee The resolved protocol fee packed for both directions (0 if nothing set)
  function getFee(PoolKey memory key) external view returns (uint24 fee);

  /// @notice Apply the resolved fee to a pool on the PoolManager
  /// @param key The pool to update
  function applyFee(PoolKey memory key) external;

  /// @notice Batch apply fees to multiple pools
  /// @param keys Array of pool keys to update
  function batchApplyFees(PoolKey[] calldata keys) external;

  /// @notice Sets the default protocol fee
  /// @dev Only callable by feeSetter. Max allowed is 1000 pips (0.1%).
  ///      The fee will be applied symmetrically to both swap directions.
  /// @param fee The new default fee value in pips (1-1000 range, or 0 to disable)
  function setDefaultFee(uint24 fee) external;

  /// @notice Sets a fee tier override
  /// @dev Only callable by feeSetter. Max allowed is 1000 pips (0.1%).
  ///      Use 0 to explicitly disable fees for this tier (distinct from clearing).
  ///      The fee will be applied symmetrically to both swap directions.
  /// @param lpFee The LP fee tier to set an override for
  /// @param protocolFee The protocol fee in pips (0 = disabled, 1-1000 = fee rate)
  function setFeeTierOverride(uint24 lpFee, uint24 protocolFee) external;

  /// @notice Sets a pool-specific override
  /// @dev Only callable by feeSetter. Max allowed is 1000 pips (0.1%).
  ///      Use 0 to explicitly disable fees for this pool (distinct from clearing).
  ///      The fee will be applied symmetrically to both swap directions.
  /// @param poolId The pool ID to set an override for
  /// @param protocolFee The protocol fee in pips (0 = disabled, 1-1000 = fee rate)
  function setPoolOverride(PoolId poolId, uint24 protocolFee) external;

  /// @notice Clears a fee tier override (reverts to next level in waterfall)
  /// @dev Only callable by feeSetter
  /// @param lpFee The LP fee tier to clear
  function clearFeeTierOverride(uint24 lpFee) external;

  /// @notice Clears a pool-specific override (reverts to next level in waterfall)
  /// @dev Only callable by feeSetter
  /// @param poolId The pool ID to clear
  function clearPoolOverride(PoolId poolId) external;

  /// @notice Sets a new fee setter address
  /// @dev Only callable by owner
  /// @param newFeeSetter The new address authorized to set fees
  function setFeeSetter(address newFeeSetter) external;

  /// @notice Collects protocol fees from the PoolManager to the TOKEN_JAR
  /// @dev Only callable by owner
  /// @param currency The currency to collect
  /// @param amount The amount to collect (0 for all available)
  /// @return amountCollected The amount actually collected
  function collectProtocolFees(Currency currency, uint256 amount)
    external
    returns (uint256 amountCollected);
}
