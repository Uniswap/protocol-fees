// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
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

  /// @notice Thrown when trying to set a default fee for a non-enabled fee tier.
  error InvalidFeeTier();

  IUniswapV3Factory public immutable FACTORY;

  address public immutable FEE_SINK;

  bytes32 public merkleRoot;
  address public feeSetter;

  mapping(uint24 feeTier => uint8 defaultFeeValue) public defaultFees;

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

  modifier onlyFeeSetter() {
    require(msg.sender == feeSetter, "UNAUTHORIZED");
    _;
  }

  /// @dev At construction, the fee setter defaults to 0 and its on the owner to set.
  constructor(address _factory, address _feeSink) Owned(msg.sender) {
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
  function setMerkleRoot(bytes32 _merkleRoot) external onlyFeeSetter {
    merkleRoot = _merkleRoot;
  }

  /// @notice Designate a default fee value for a given fee tier. Only callable by the feeSetter
  /// @dev performs NO validation if the default fee value is indeed valid
  /// @param feeTier The fee tier to set the default fee for.
  /// @param defaultFeeValue The default fee value to set. Expressed as the denominator on the
  /// inclusive interval [4, 10]
  function setDefaultFeeByFeeTier(uint24 feeTier, uint8 defaultFeeValue) external onlyFeeSetter {
    if (FACTORY.feeAmountTickSpacing(feeTier) == 0) revert InvalidFeeTier();
    defaultFees[feeTier] = defaultFeeValue;
  }

  /// @notice Triggers the fee update for the given pool.
  /// @param pool The pool address to update the fee for.
  /// @param proof The merkle proof corresponding to the set merkle root. Merkle root is generated
  /// from leaves of keccak256(abi.encode(pool)).
  function triggerFeeUpdate(address pool, bytes32[] calldata proof) external {
    bytes32 node = keccak256(abi.encode(pool));
    if (!MerkleProof.verify(proof, merkleRoot, node)) revert InvalidProof();

    uint8 feeValue = defaultFees[IUniswapV3Pool(pool).fee()];

    IUniswapV3PoolOwnerActions(pool).setFeeProtocol(feeValue % 16, feeValue >> 4);
  }

  /// @notice Set a new `feeSetter` address. Only callable by owner
  /// @dev Performs no validation checks
  /// @param newFeeSetter The new fee setter address.
  function setFeeSetter(address newFeeSetter) external onlyOwner {
    feeSetter = newFeeSetter;
  }
}
