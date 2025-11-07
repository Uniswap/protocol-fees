// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";

interface IV3FeeAdapter {
  /// @notice Thrown when the merkle proof is invalid.
  error InvalidProof();

  /// @notice Thrown when trying to set a default fee for a non-enabled fee tier.
  error InvalidFeeTier();

  /// @notice Thrown when an unauthorized address attempts to call a restricted function
  error Unauthorized();

  /// @notice Thrown when trying to store a fee tier that is already stored.
  error TierAlreadyStored();

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

  /// @notice The pair of tokens to trigger fees for. Each node in the merkle tree is the sorted
  /// pair. If one pair in the merkle tree is (USDC, USDT), all pools consisting of those tokens
  /// will be allowed to have a fee enabled.
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

  /// @return The current merkle root used to designate which pools have a fee enabled
  function merkleRoot() external view returns (bytes32);

  /// @return The authorized address to set fees-by-fee-tier AND the merkle root
  function feeSetter() external view returns (address);

  /// @return The fee tiers enabled on the factory
  function feeTiers(uint256 i) external view returns (uint24);

  /// @notice Stores a fee tier.
  /// @param feeTier The fee tier to store.
  /// @dev Must be a fee tier that exists on the Uniswap V3 Factory.
  function storeFeeTier(uint24 feeTier) external;

  /// @notice Returns the default fee value for a given fee tier.
  /// @param feeTier The fee tier to query.
  /// @return defaultFeeValue The default fee value expressed as the denominator on the inclusive
  /// interval [4, 10]. The fee value is packed (token1Fee << 4 | token0Fee)
  function defaultFees(uint24 feeTier) external view returns (uint8 defaultFeeValue);

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

  /// @notice Sets the merkle root used for designating which pools have the fee enabled.
  /// @dev Only callable by `feeSetter`
  /// @param _merkleRoot The new merkle root to set.
  function setMerkleRoot(bytes32 _merkleRoot) external;

  /// @notice Sets the default fee value for a specific fee tier.
  /// @param feeTier The fee tier, expressed in pips, to set the default fee for.
  /// @param defaultFeeValue The default fee value to set, expressed as the denominator on the
  /// inclusive interval [4, 10]. The fee value is packed (token1Fee << 4 | token0Fee)
  function setDefaultFeeByFeeTier(uint24 feeTier, uint8 defaultFeeValue) external;

  /// @notice Triggers a fee update for a single pool with merkle proof verification.
  /// @param pool The pool address to update the fee for.
  /// @param merkleProof The merkle proof corresponding to the set merkle root.
  function triggerFeeUpdate(address pool, bytes32[] calldata merkleProof) external;

  /// @notice Triggers a fee update for one pair of tokens with merkle proof verification. There may
  /// be multiple pools initialized from the given pair.
  /// @param token0 The first token of the pair.
  /// @param token1 The second token of the pair.
  /// @param proof The merkle proof corresponding to the set merkle root.
  /// @dev Assumes that token0 < token1.
  function triggerFeeUpdate(address token0, address token1, bytes32[] calldata proof) external;

  /// @notice Triggers fee updates for multiple pairs of tokens with batch merkle proof
  /// verification.
  /// @param pairs The pair of two tokens. There may be multiple pools initialized from the same
  /// pair.
  /// @param proof The merkle proof corresponding to the set merkle root.
  /// @param proofFlags The flags for the merkle proof verification.
  /// @dev Assumes that token0 < token1 in the token pair.
  function batchTriggerFeeUpdate(
    Pair[] calldata pairs,
    bytes32[] calldata proof,
    bool[] calldata proofFlags
  ) external;

  /// @notice Sets a new fee setter address.
  /// @param newFeeSetter The new address authorized to set fees and merkle roots.
  function setFeeSetter(address newFeeSetter) external;
}
