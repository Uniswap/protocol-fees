// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Owned} from "solmate/src/auth/Owned.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3PoolOwnerActions} from
  "v3-core/contracts/interfaces/pool/IUniswapV3PoolOwnerActions.sol";
import {MerkleProof} from "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import {IV3FeeController} from "../interfaces/IV3FeeController.sol";
import {ArrayLib} from "../libraries/ArrayLib.sol";

/// @title V3FeeController
/// @notice A contract that allows the setting and collecting of protocol fees per pool, and adding
/// new fee tiers to the Uniswap V3 Factory.
/// @dev This contract is ownable. The owner can set the merkle root for proving protocol fee
/// amounts per pool, set new fee tiers on Uniswap V3, and change the owner of this contract.
/// Note that this contract will be the set owner on the Uniswap V3 Factory.
/// @custom:security-contact security@uniswap.org
contract V3FeeController is IV3FeeController, Owned {
  using ArrayLib for uint24[];

  /// @inheritdoc IV3FeeController
  IUniswapV3Factory public immutable FACTORY;
  /// @inheritdoc IV3FeeController
  address public immutable ASSET_SINK;

  /// @inheritdoc IV3FeeController
  bytes32 public merkleRoot;

  /// @inheritdoc IV3FeeController
  address public feeSetter;

  /// @inheritdoc IV3FeeController
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
  constructor(address _factory, address _assetSink) Owned(msg.sender) {
    FACTORY = IUniswapV3Factory(_factory);
    ASSET_SINK = _assetSink;
  }

  /// @inheritdoc IV3FeeController
  function storeFeeTier(uint24 feeTier) public {
    require(_feeTierExists(feeTier), InvalidFeeTier());
    require(!feeTiers.includes(feeTier), TierAlreadyStored());
    feeTiers.push(feeTier);
  }

  /// @inheritdoc IV3FeeController
  function enableFeeAmount(uint24 fee, int24 tickSpacing) external onlyOwner {
    FACTORY.enableFeeAmount(fee, tickSpacing);

    storeFeeTier(fee);
  }

  function setFactoryOwner(address newOwner) external onlyOwner {
    FACTORY.setOwner(newOwner);
  }

  /// @inheritdoc IV3FeeController
  function collect(CollectParams[] calldata collectParams)
    external
    returns (Collected[] memory amountsCollected)
  {
    amountsCollected = new Collected[](collectParams.length);
    for (uint256 i = 0; i < collectParams.length; i++) {
      CollectParams calldata params = collectParams[i];
      (uint256 amount0Collected, uint256 amount1Collected) = IUniswapV3PoolOwnerActions(params.pool)
        .collectProtocol(ASSET_SINK, params.amount0Requested, params.amount1Requested);

      amountsCollected[i] = Collected({
        amount0Collected: uint128(amount0Collected),
        amount1Collected: uint128(amount1Collected)
      });
    }
  }

  /// @inheritdoc IV3FeeController
  function setMerkleRoot(bytes32 _merkleRoot) external onlyFeeSetter {
    merkleRoot = _merkleRoot;
  }

  /// @inheritdoc IV3FeeController
  function setDefaultFeeByFeeTier(uint24 feeTier, uint8 defaultFeeValue) external onlyFeeSetter {
    require(_feeTierExists(feeTier), InvalidFeeTier());
    defaultFees[feeTier] = defaultFeeValue;
  }

  /// @inheritdoc IV3FeeController
  function setFeeSetter(address newFeeSetter) external onlyOwner {
    feeSetter = newFeeSetter;
  }

  /// @inheritdoc IV3FeeController
  function triggerFeeUpdate(address pool, bytes32[] calldata proof) external {
    bytes32 node = _doubleHash(IUniswapV3Pool(pool).token0(), IUniswapV3Pool(pool).token1());
    if (!MerkleProof.verify(proof, merkleRoot, node)) revert InvalidProof();

    _setProtocolFee(pool, IUniswapV3Pool(pool).fee());
  }

  /// @inheritdoc IV3FeeController
  function triggerFeeUpdate(address token0, address token1, bytes32[] calldata proof) external {
    bytes32 node = _doubleHash(token0, token1);
    if (!MerkleProof.verify(proof, merkleRoot, node)) revert InvalidProof();

    _setProtocolFeesForPair(token0, token1);
  }

  /// @inheritdoc IV3FeeController
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

  function _setProtocolFee(address pool, uint24 feeTier) internal {
    uint8 feeValue = defaultFees[feeTier];
    IUniswapV3PoolOwnerActions(pool).setFeeProtocol(feeValue % 16, feeValue >> 4);
  }

  function _doubleHash(address token0, address token1) internal pure returns (bytes32 poolHash) {
    // keccak256(abi.encode(keccak256(abi.encode(token0, token1))));
    assembly ("memory-safe") {
      mstore(0x00, and(token0, 0xffffffffffffffffffffffffffffffffffffffff))
      mstore(0x20, and(token1, 0xffffffffffffffffffffffffffffffffffffffff))
      mstore(0x00, keccak256(0x00, 0x40))
      poolHash := keccak256(0x00, 0x20)
    }
  }

  function _feeTierExists(uint24 feeTier) internal view returns (bool) {
    if (FACTORY.feeAmountTickSpacing(feeTier) == 0) return false;
    return true;
  }
}
