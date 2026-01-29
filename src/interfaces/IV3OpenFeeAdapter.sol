// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";

/// @title IV3OpenFeeAdapter
/// @notice Interface for a permissionless fee adapter that allows anyone to trigger fee updates
/// @dev This is a simplified version of IV3FeeAdapter that removes Merkle proof authorization
interface IV3OpenFeeAdapter {
  /// @notice Thrown when trying to set a default fee for a non-enabled fee tier.
  error InvalidFeeTier();

  /// @notice Thrown when an unauthorized address attempts to call a restricted function
  error Unauthorized();

  /// @notice Thrown when trying to store a fee tier that is already stored.
  error TierAlreadyStored();

  /// @notice Thrown when trying to set an invalid fee value that doesn't meet protocol
  /// requirements.
  error InvalidFeeValue();

  /// @notice Emitted when a fee update is triggered for a pool
  /// @param caller The address that triggered the update
  /// @param pool The pool that was updated
  /// @param feeValue The new fee value applied
  event FeeUpdateTriggered(address indexed caller, address indexed pool, uint8 feeValue);

  /// @notice Emitted when a batch fee update is triggered
  /// @param caller The address that triggered the update
  /// @param pairsUpdated The number of pairs processed
  /// @param poolsAffected The number of pools that were actually updated
  event BatchFeeUpdateTriggered(
    address indexed caller, uint256 pairsUpdated, uint256 poolsAffected
  );

  /// @notice The input parameters for the collection.
  struct CollectParams {
    /// @param pool The pool to collect fees from.
    address pool;
    /// @param amount0Requested The amount of token0 to collect. If this is higher than the total
    /// collectable amount, it will collect all but 1 wei of the total token0 allotment.
    uint128 amount0Requested;
    /// @param amount1Requested The amount of token1 to collect. If this is higher than the total
    /// collectable amount, it will collect all but 1 wei of the total token1 allotment.
    uint128 amount1Requested;
  }

  /// @notice The returned amounts of token0 and token1 that are collected.
  struct Collected {
    /// @param amount0Collected The amount of token0 that is collected.
    uint128 amount0Collected;
    /// @param amount1Collected The amount of token1 that is collected.
    uint128 amount1Collected;
  }

  /// @notice The pair of tokens to trigger fees for.
  struct Pair {
    /// @param token0 The first token of the pair.
    address token0;
    /// @param token1 The second token of the pair.
    address token1;
  }

  /// @return The address where collected fees are sent.
  function TOKEN_JAR() external view returns (address);

  /// @return The Uniswap V3 Factory contract.
  function FACTORY() external view returns (IUniswapV3Factory);

  /// @return The authorized address to set fees-by-fee-tier
  function feeSetter() external view returns (address);

  /// @return The fee tiers enabled on the factory
  function feeTiers(uint256 i) external view returns (uint24);

  /// @notice Returns the default fee value for a given fee tier.
  /// @param feeTier The fee tier to query.
  /// @return defaultFeeValue The default fee value expressed as the denominator on the inclusive
  /// interval [4, 10]. The fee value is packed (token1Fee << 4 | token0Fee)
  function defaultFees(uint24 feeTier) external view returns (uint8 defaultFeeValue);

  /// @notice Stores a fee tier.
  /// @param feeTier The fee tier to store.
  /// @dev Must be a fee tier that exists on the Uniswap V3 Factory.
  function storeFeeTier(uint24 feeTier) external;

  /// @notice Enables a new fee tier on the Uniswap V3 Factory.
  /// @dev Only callable by `owner`. Also updates the `feeTiers` array.
  /// @param newFeeTier The fee tier to enable.
  /// @param tickSpacing The corresponding tick spacing for the new fee tier.
  function enableFeeAmount(uint24 newFeeTier, int24 tickSpacing) external;

  /// @notice Sets the owner of the Uniswap V3 Factory.
  /// @dev Only callable by `owner`
  /// @param newOwner The new owner of the Uniswap V3 Factory.
  function setFactoryOwner(address newOwner) external;

  /// @notice Collects protocol fees from the specified pools to the designated `TOKEN_JAR`
  /// @param collectParams Array of collection parameters for each pool.
  /// @return amountsCollected Array of collected amounts for each pool.
  function collect(CollectParams[] calldata collectParams)
    external
    returns (Collected[] memory amountsCollected);

  /// @notice Sets the default fee value for a specific fee tier.
  /// @dev Only callable by `feeSetter`
  /// @param feeTier The fee tier, expressed in pips, to set the default fee for.
  /// @param defaultFeeValue The default fee value to set, expressed as the denominator on the
  /// inclusive interval [4, 10]. The fee value is packed (token1Fee << 4 | token0Fee)
  function setDefaultFeeByFeeTier(uint24 feeTier, uint8 defaultFeeValue) external;

  /// @notice Sets a new fee setter address.
  /// @dev Only callable by `owner`
  /// @param newFeeSetter The new address authorized to set fees.
  function setFeeSetter(address newFeeSetter) external;

  /// @notice Triggers a fee update for a single pool. Permissionless.
  /// @param pool The pool address to update the fee for.
  function triggerFeeUpdate(address pool) external;

  /// @notice Triggers a fee update for one pair of tokens. Permissionless.
  /// @dev There may be multiple pools initialized from the given pair.
  /// @param token0 The first token of the pair.
  /// @param token1 The second token of the pair.
  function triggerFeeUpdate(address token0, address token1) external;

  /// @notice Triggers fee updates for multiple pairs of tokens. Permissionless.
  /// @param pairs The pairs of two tokens. There may be multiple pools initialized from the same
  /// pair.
  function batchTriggerFeeUpdate(Pair[] calldata pairs) external;

  /// @notice Triggers fee updates for multiple pools directly. Permissionless.
  /// @param pools The pool addresses to update the fees for.
  function batchTriggerFeeUpdateByPool(address[] calldata pools) external;
}
