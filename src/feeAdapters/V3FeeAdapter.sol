// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Owned} from "solmate/src/auth/Owned.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {
  IUniswapV3PoolOwnerActions
} from "v3-core/contracts/interfaces/pool/IUniswapV3PoolOwnerActions.sol";
import {MerkleProof} from "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import {IV3FeeAdapter} from "../interfaces/IV3FeeAdapter.sol";
import {ArrayLib} from "../libraries/ArrayLib.sol";

/// @title V3FeeAdapter
/// @notice A contract that allows the setting and collecting of protocol fees per pool, and adding
/// new fee tiers to the Uniswap V3 Factory.
/// @dev This contract is ownable. The owner can set the merkle root for proving protocol fee
/// amounts per pool, set new fee tiers on Uniswap V3, and change the owner of this contract.
/// Note that this contract will be the set owner on the Uniswap V3 Factory.
/// @custom:security-contact security@uniswap.org
contract V3FeeAdapter is IV3FeeAdapter, Owned {
  using ArrayLib for uint24[];

  /// @inheritdoc IV3FeeAdapter
  IUniswapV3Factory public immutable FACTORY;
  /// @inheritdoc IV3FeeAdapter
  address public immutable TOKEN_JAR;

  /// @inheritdoc IV3FeeAdapter
  bytes32 public merkleRoot;

  /// @inheritdoc IV3FeeAdapter
  address public feeSetter;

  /// @inheritdoc IV3FeeAdapter
  mapping(uint24 feeTier => uint8 defaultFeeValue) public defaultFees;

  /// @return The fee tiers that are enabled on the factory. Iterable so that the protocol fee for
  /// pools of the same pair can be activated with the same merkle proof.
  /// @dev Returns four enabled fee tiers: 100, 500, 3000, 10000. May return more if more are
  /// enabled.
  uint24[] public feeTiers;

  /// @notice Ensures only the fee setter can call the setMerkleRoot and setDefaultFeeByFeeTier
  /// functions
  modifier onlyFeeSetter() {
    require(msg.sender == feeSetter, Unauthorized());
    _;
  }

  /// @dev At construction, the fee setter defaults to 0 and its on the owner to set.
  constructor(address _factory, address _tokenJar) Owned(msg.sender) {
    FACTORY = IUniswapV3Factory(_factory);
    TOKEN_JAR = _tokenJar;
  }

  /// @inheritdoc IV3FeeAdapter
  function storeFeeTier(uint24 feeTier) public {
    require(_feeTierExists(feeTier), InvalidFeeTier());
    require(!feeTiers.includes(feeTier), TierAlreadyStored());
    feeTiers.push(feeTier);
  }

  /// @inheritdoc IV3FeeAdapter
  function enableFeeAmount(uint24 fee, int24 tickSpacing) external onlyOwner {
    FACTORY.enableFeeAmount(fee, tickSpacing);

    storeFeeTier(fee);
  }

  /// @notice Transfer ownership of the Uniswap V3 Factory to a new address
  /// @dev Only callable by the owner of this contract. This is a critical operation
  ///      as it transfers control of the V3 Factory
  /// @param newOwner The address that will become the new owner of the V3 Factory
  function setFactoryOwner(address newOwner) external onlyOwner {
    FACTORY.setOwner(newOwner);
  }

  /// @inheritdoc IV3FeeAdapter
  function collect(CollectParams[] calldata collectParams)
    external
    returns (Collected[] memory amountsCollected)
  {
    amountsCollected = new Collected[](collectParams.length);
    for (uint256 i = 0; i < collectParams.length; i++) {
      CollectParams calldata params = collectParams[i];
      (uint128 amount0Collected, uint128 amount1Collected) = IUniswapV3PoolOwnerActions(params.pool)
        .collectProtocol(TOKEN_JAR, params.amount0Requested, params.amount1Requested);

      amountsCollected[i] =
        Collected({amount0Collected: amount0Collected, amount1Collected: amount1Collected});
    }
  }

  /// @inheritdoc IV3FeeAdapter
  function setMerkleRoot(bytes32 _merkleRoot) external onlyFeeSetter {
    merkleRoot = _merkleRoot;
  }

  /// @inheritdoc IV3FeeAdapter
  function setDefaultFeeByFeeTier(uint24 feeTier, uint8 defaultFeeValue) external onlyFeeSetter {
    require(_feeTierExists(feeTier), InvalidFeeTier());
    // Extract the two 4-bit values
    uint8 feeProtocol0 = defaultFeeValue % 16;
    uint8 feeProtocol1 = defaultFeeValue >> 4;
    // Validate both values match pool requirements: must be 0 or in range [4, 10]
    require(
      (feeProtocol0 == 0 || (feeProtocol0 >= 4 && feeProtocol0 <= 10)) &&
      (feeProtocol1 == 0 || (feeProtocol1 >= 4 && feeProtocol1 <= 10)),
      InvalidFeeValue()
    );
    defaultFees[feeTier] = defaultFeeValue;
  }

  /// @inheritdoc IV3FeeAdapter
  function setFeeSetter(address newFeeSetter) external onlyOwner {
    feeSetter = newFeeSetter;
  }

  /// @inheritdoc IV3FeeAdapter
  function triggerFeeUpdate(address pool, bytes32[] calldata proof) external {
    bytes32 node = _doubleHash(IUniswapV3Pool(pool).token0(), IUniswapV3Pool(pool).token1());
    if (!MerkleProof.verify(proof, merkleRoot, node)) revert InvalidProof();

    _setProtocolFee(pool, IUniswapV3Pool(pool).fee());
  }

  /// @inheritdoc IV3FeeAdapter
  function triggerFeeUpdate(address token0, address token1, bytes32[] calldata proof) external {
    bytes32 node = _doubleHash(token0, token1);
    if (!MerkleProof.verify(proof, merkleRoot, node)) revert InvalidProof();

    _setProtocolFeesForPair(token0, token1);
  }

  /// @inheritdoc IV3FeeAdapter
  function batchTriggerFeeUpdate(
    Pair[] calldata pairs,
    bytes32[] calldata proof,
    bool[] calldata proofFlags
  ) external {
    bytes32[] memory leaves = new bytes32[](pairs.length);
    Pair memory pair;
    for (uint256 i; i < pairs.length; i++) {
      pair = pairs[i];
      leaves[i] = _doubleHash(pair.token0, pair.token1);
      _setProtocolFeesForPair(pair.token0, pair.token1);
    }
    require(MerkleProof.multiProofVerify(proof, proofFlags, merkleRoot, leaves), InvalidProof());
  }

  /// @notice Sets protocol fees for all existing pools of a token pair across all fee tiers
  /// @dev Iterates through all stored fee tiers and sets the protocol fee for each pool that exists
  /// @param token0 The first token of the pair
  /// @param token1 The second token of the pair
  function _setProtocolFeesForPair(address token0, address token1) internal {
    uint24 feeTier;
    address pool;
    uint256 length = feeTiers.length;
    for (uint256 i; i < length; i++) {
      feeTier = feeTiers[i];
      pool = FACTORY.getPool(token0, token1, feeTier);
      if (pool != address(0)) _setProtocolFee(pool, feeTier);
    }
  }

  /// @notice Sets the protocol fee for a specific pool based on its fee tier
  /// @dev Only sets the fee for initialized pools (sqrtPriceX96 != 0)
  ///      The feeValue encodes both fee0 (lower 4 bits) and fee1 (upper 4 bits)
  /// @param pool The address of the Uniswap V3 pool
  /// @param feeTier The fee tier of the pool, used to look up the default fee value
  function _setProtocolFee(address pool, uint24 feeTier) internal {
    // Check if pool is initialized by verifying sqrtPriceX96 is non-zero
    (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
    if (sqrtPriceX96 == 0) return; // Pool exists but not initialized, skip

    uint8 feeValue = defaultFees[feeTier];
    IUniswapV3PoolOwnerActions(pool).setFeeProtocol(feeValue % 16, feeValue >> 4);
  }

  /// @notice Computes a double hash of token addresses for Merkle tree verification
  /// @dev Performs keccak256(abi.encode(keccak256(abi.encode(token0, token1))))
  ///      Uses assembly for gas optimization
  /// @param token0 The first token address
  /// @param token1 The second token address
  /// @return poolHash The double hash result used as a Merkle tree leaf
  function _doubleHash(address token0, address token1) internal pure returns (bytes32 poolHash) {
    // keccak256(abi.encode(keccak256(abi.encode(token0, token1))));
    assembly ("memory-safe") {
      mstore(0x00, and(token0, 0xffffffffffffffffffffffffffffffffffffffff))
      mstore(0x20, and(token1, 0xffffffffffffffffffffffffffffffffffffffff))
      mstore(0x00, keccak256(0x00, 0x40))
      poolHash := keccak256(0x00, 0x20)
    }
  }

  /// @notice Checks if a fee tier exists in the Uniswap V3 Factory
  /// @dev Verifies existence by checking if the tick spacing for the fee tier is non-zero
  /// @param feeTier The fee tier to check
  /// @return True if the fee tier exists, false otherwise
  function _feeTierExists(uint24 feeTier) internal view returns (bool) {
    if (FACTORY.feeAmountTickSpacing(feeTier) == 0) return false;
    return true;
  }
}
