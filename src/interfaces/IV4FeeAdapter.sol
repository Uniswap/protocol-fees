// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IV4FeePolicy} from "./IV4FeePolicy.sol";

/// @title IV4FeeAdapter
/// @notice Interface for the V4 fee adapter — the protocolFeeController registered on the
/// PoolManager. Resolves fees via pool overrides or policy delegation, triggers fee updates,
/// and collects accrued fees to the TokenJar.
/// @custom:security-contact security@uniswap.org
interface IV4FeeAdapter {
  // --- Errors ---

  /// @notice Thrown when an unauthorized address calls a restricted function.
  error Unauthorized();

  /// @notice Thrown when a fee value fails ProtocolFeeLibrary.isValidProtocolFee.
  error InvalidFeeValue();

  // --- Events ---

  /// @notice Emitted when the policy contract is updated.
  /// @param oldPolicy The previous policy address.
  /// @param newPolicy The new policy address.
  event PolicyUpdated(address indexed oldPolicy, address indexed newPolicy);

  /// @notice Emitted when a pool override is set or removed.
  /// @param poolId The pool whose override changed.
  /// @param feeValue The new fee value (0 means override was removed).
  event PoolOverrideUpdated(PoolId indexed poolId, uint24 feeValue);

  /// @notice Emitted when the fee setter address is updated.
  /// @param oldFeeSetter The previous fee setter address.
  /// @param newFeeSetter The new fee setter address.
  event FeeSetterUpdated(address indexed oldFeeSetter, address indexed newFeeSetter);

  /// @notice Emitted when a fee update is triggered for a pool.
  /// @param caller The address that triggered the update.
  /// @param poolId The pool that was updated.
  /// @param feeValue The protocol fee that was set on the PoolManager.
  event FeeUpdateTriggered(address indexed caller, PoolId indexed poolId, uint24 feeValue);

  /// @notice Emitted when protocol fees are collected.
  /// @param currency The currency that was collected.
  /// @param amount The amount collected.
  event FeesCollected(Currency indexed currency, uint256 amount);

  // --- Structs ---

  /// @notice Parameters for collecting protocol fees.
  struct CollectParams {
    /// @dev The currency to collect.
    Currency currency;
    /// @dev The amount to collect. 0 = collect all accrued.
    uint256 amount;
  }

  // --- Immutables ---

  /// @notice The Uniswap V4 PoolManager this adapter controls fees for.
  /// @return The PoolManager contract.
  function POOL_MANAGER() external view returns (IPoolManager);

  /// @notice The address where collected fees are sent.
  /// @return The TokenJar address.
  function TOKEN_JAR() external view returns (address);

  /// @notice Sentinel value representing an explicit zero fee in storage.
  /// @dev type(uint24).max — safe because isValidProtocolFee rejects it.
  /// @return The sentinel value (0xFFFFFF).
  function ZERO_FEE_SENTINEL() external pure returns (uint24);

  // --- State ---

  /// @notice The address authorized to set pool overrides.
  /// @return The current fee setter address.
  function feeSetter() external view returns (address);

  /// @notice The current fee policy contract.
  /// @return The policy contract address.
  function policy() external view returns (IV4FeePolicy);

  /// @notice Returns the pool-specific fee override.
  /// @param poolId The pool to query.
  /// @return The sentinel-encoded fee override. 0 = not set.
  function poolOverrides(PoolId poolId) external view returns (uint24);

  // --- Admin (onlyOwner) ---

  /// @notice Sets the fee policy contract. Only callable by owner.
  /// @dev Setting address(0) disables policy — all non-overridden pools get fee 0.
  /// @param newPolicy The new policy contract address.
  function setPolicy(IV4FeePolicy newPolicy) external;

  /// @notice Sets the fee setter address. Only callable by owner.
  /// @param newFeeSetter The new fee setter address.
  function setFeeSetter(address newFeeSetter) external;

  // --- Pool Overrides (onlyFeeSetter) ---

  /// @notice Sets a pool-specific fee override (highest priority in waterfall).
  /// @dev Setting 0 sets an explicit zero fee (does NOT fall through to policy).
  /// Use clearPoolOverride to remove the override entirely.
  /// @param poolId The pool to override.
  /// @param feeValue The protocol fee to set. Must pass isValidProtocolFee if non-zero.
  function setPoolOverride(PoolId poolId, uint24 feeValue) external;

  /// @notice Removes a pool-specific fee override, falling through to policy.
  /// @param poolId The pool to clear the override for.
  function clearPoolOverride(PoolId poolId) external;

  // --- Fee Resolution ---

  /// @notice Resolves the protocol fee for a pool: pool override → policy → 0.
  /// @param key The pool key to resolve the fee for.
  /// @return fee The resolved protocol fee.
  function getFee(PoolKey memory key) external view returns (uint24 fee);

  // --- Permissionless Triggering ---

  /// @notice Triggers a fee update for a single pool. Permissionless.
  /// @dev Silently skips uninitialized pools (sqrtPriceX96 == 0).
  /// @param key The pool key to update.
  function triggerFeeUpdate(PoolKey calldata key) external;

  /// @notice Triggers fee updates for multiple pools. Permissionless.
  /// @dev Silently skips uninitialized pools.
  /// @param keys The pool keys to update.
  function batchTriggerFeeUpdate(PoolKey[] calldata keys) external;

  // --- Collection ---

  /// @notice Collects protocol fees to the TOKEN_JAR. Permissionless.
  /// @dev Safe because funds always go to the immutable TOKEN_JAR. The PoolManager
  /// enforces that only the protocolFeeController (this contract) can call
  /// collectProtocolFees.
  /// @param params Array of currencies and amounts to collect.
  function collect(CollectParams[] calldata params) external;
}
