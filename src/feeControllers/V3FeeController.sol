// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3PoolOwnerActions} from
  "v3-core/contracts/interfaces/pool/IUniswapV3PoolOwnerActions.sol";
import {MerkleProof} from "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

/// @title V3FeeController
/// @notice A contract that allows the setting and collecting of protocol fees per pool, and adding
/// new fee tiers to the Uniswap V3 Factory.
/// @dev This contract is ownable. The owner can set the merkle root for proving protocol fee
/// amounts per pool, set new fee tiers on Uniswap V3, and change the owner of this contract.
/// Note that this contract will be the set owner on the Uniswap V3 Factory.
contract V3FeeController is Owned {
  /// @notice Thrown when the amount collected is less than the amount expected.
  error AmountCollectedTooLow(uint256 amountCollected, uint256 amountExpected);

  /// @notice Thrown when the merkle proof is invalid.
  error InvalidProof();

  IUniswapV3Factory public immutable FACTORY;

  address public immutable FEE_SINK;

  bytes32 public merkleRoot;

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

  constructor(address _factory, address _feeSink, address _owner) Owned(_owner) {
    FACTORY = IUniswapV3Factory(_factory);
    FEE_SINK = _feeSink;
  }

  /// @notice Enables new fee tiers on the Uniswap V3 Factory.
  /// @param fee The fee amount to enable.
  /// @param tickSpacing The corresponding tick spacing to enable.
  function enableFeeAmount(uint24 fee, int24 tickSpacing) external onlyOwner {
    FACTORY.enableFeeAmount(fee, tickSpacing);
  }

  /// @notice Collects the protocol fees for the given pool.
  /// @param collectParams The parameters for the collection. See CollectParams for more details.
  function collect(CollectParams[] calldata collectParams)
    external
    returns (Collected[] memory amountsCollected)
  {
    amountsCollected = new Collected[](collectParams.length);
    for (uint256 i = 0; i < collectParams.length; i++) {
      CollectParams calldata params = collectParams[i];
      (uint256 amount0Collected, uint256 amount1Collected) = IUniswapV3PoolOwnerActions(params.pool)
        .collectProtocol(FEE_SINK, params.amount0Requested, params.amount1Requested);

      amountsCollected[i] = Collected({
        amount0Collected: uint128(amount0Collected),
        amount1Collected: uint128(amount1Collected)
      });
    }
  }

  /// @notice Sets the merkle root for the fee controller.
  /// @dev only callable by owner
  /// @param _merkleRoot The merkle root to set.
  function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
    merkleRoot = _merkleRoot;
  }

  /// @notice Triggers the fee update for the given pool.
  /// @param pool The pool address to update the fee for.
  /// @param feeProtocol0 The new protocol fee for token0.
  /// @param feeProtocol1 The new protocol fee for token1.
  /// @param proof The merkle proof corresponding to the set merkle root. Merkle root is generated
  /// from leaves of keccak256(abi.encode(pool, feeProtocol0, feeProtocol1)).
  function triggerFeeUpdate(
    address pool,
    uint8 feeProtocol0,
    uint8 feeProtocol1,
    bytes32[] calldata proof
  ) external {
    bytes32 node = keccak256(abi.encode(pool, feeProtocol0, feeProtocol1));
    if (!MerkleProof.verify(proof, merkleRoot, node)) revert InvalidProof();

    IUniswapV3PoolOwnerActions(pool).setFeeProtocol(feeProtocol0, feeProtocol1);
  }
}
