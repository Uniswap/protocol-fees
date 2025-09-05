// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IAssetSink} from "./IAssetSink.sol";

interface IV3FeeController {
  /// @notice Thrown when the amount collected is less than the amount expected.
  error AmountCollectedTooLow(uint256 amountCollected, uint256 amountExpected);

  /// @notice Thrown when the merkle proof is invalid.
  error InvalidProof();

  /// @notice Thrown when trying to set a default fee for a non-enabled fee tier.
  error InvalidFeeTier();

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

  /// @notice Returns the address where collected fees are sent.
  function FEE_SINK() external view returns (address);

  /// @notice Returns the Uniswap V3 Factory contract.
  function FACTORY() external view returns (IUniswapV3Factory);

  /// @notice Returns the current merkle root used for fee update proofs.
  function merkleRoot() external view returns (bytes32);

  /// @notice Returns the address authorized to set fees and merkle roots.
  function feeSetter() external view returns (address);

  /// @notice Returns the default fee value for a given fee tier.
  /// @param feeTier The fee tier to query.
  /// @return defaultFeeValue The default fee value expressed as the denominator on the inclusive
  /// interval [4, 10].
  function defaultFees(uint24 feeTier) external view returns (uint8 defaultFeeValue);
  /// @notice Enables a new fee tier on the Uniswap V3 Factory.
  /// @param newFeeTier The fee amount to enable.
  /// @param tickSpacing The corresponding tick spacing for the fee tier.
  function enableFeeAmount(uint24 newFeeTier, int24 tickSpacing) external;

  /// @notice Collects protocol fees from the specified pools.
  /// @param collectParams Array of collection parameters for each pool.
  /// @return amountsCollected Array of collected amounts for each pool.
  function collect(CollectParams[] calldata collectParams)
    external
    returns (Collected[] memory amountsCollected);

  /// @notice Sets the merkle root used for verifying fee update proofs.
  /// @param _merkleRoot The new merkle root to set.
  function setMerkleRoot(bytes32 _merkleRoot) external;

  /// @notice Sets the default fee value for a specific fee tier.
  /// @param feeTier The fee tier to set the default fee for.
  /// @param defaultFeeValue The default fee value to set, expressed as the denominator on the
  /// inclusive interval [4, 10].
  function setDefaultFeeByFeeTier(uint24 feeTier, uint8 defaultFeeValue) external;

  /// @notice Triggers a fee update for a single pool with merkle proof verification.
  /// @param pool The pool address to update the fee for.
  /// @param merkleProof The merkle proof corresponding to the set merkle root.
  function triggerFeeUpdate(address pool, bytes32[] calldata merkleProof) external;

  /// @notice Triggers fee updates for multiple pools with batch merkle proof verification.
  /// @param pools The pool addresses to update fees for.
  /// @param proof The merkle proof corresponding to the set merkle root.
  /// @param proofFlags The flags for the merkle proof verification.
  function batchTriggerFeeUpdate(
    address[] calldata pools,
    bytes32[] calldata proof,
    bool[] calldata proofFlags
  ) external;

  /// @notice Sets a new fee setter address.
  /// @param newFeeSetter The new address authorized to set fees and merkle roots.
  function setFeeSetter(address newFeeSetter) external;
}
