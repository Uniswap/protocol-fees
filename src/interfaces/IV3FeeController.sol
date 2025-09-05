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

  function FEE_SINK() external view returns (address);
  function FACTORY() external view returns (IUniswapV3Factory);
  function merkleRoot() external view returns (bytes32);
  function feeSetter() external view returns (address);
  function defaultFees(uint24 feeTier) external view returns (uint8 defaultFeeValue);
  function enableFeeAmount(uint24 newFeeTier, int24 tickSpacing) external;
  function collect(CollectParams[] calldata collectParams)
    external
    returns (Collected[] memory amountsCollected);

  function setMerkleRoot(bytes32 _merkleRoot) external;
  function setDefaultFeeByFeeTier(uint24 feeTier, uint8 defaultFeeValue) external;
  function triggerFeeUpdate(address pool, bytes32[] calldata merkleProof) external;

  function setFeeSetter(address newFeeSetter) external;
}
