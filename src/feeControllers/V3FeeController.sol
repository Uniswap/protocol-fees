// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3PoolOwnerActions} from
  "v3-core/contracts/interfaces/pool/IUniswapV3PoolOwnerActions.sol";
import {MerkleProof} from "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import {IV3FeeController} from "../interfaces/IV3FeeController.sol";

/// @title V3FeeController
/// @notice A contract that allows the setting and collecting of protocol fees per pool, and adding
/// new fee tiers to the Uniswap V3 Factory.
/// @dev This contract is ownable. The owner can set the merkle root for proving protocol fee
/// amounts per pool, set new fee tiers on Uniswap V3, and change the owner of this contract.
/// Note that this contract will be the set owner on the Uniswap V3 Factory.
contract V3FeeController is IV3FeeController, Owned {
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

  /// @notice Ensures only the fee setter can call the setMerkleRoot and setDefaultFeeByFeeTier
  /// functions
  modifier onlyFeeSetter() {
    if (msg.sender != feeSetter) revert Unauthorized();
    _;
  }

  /// @dev At construction, the fee setter defaults to 0 and its on the owner to set.
  constructor(address _factory, address _assetSink) Owned(msg.sender) {
    FACTORY = IUniswapV3Factory(_factory);
    ASSET_SINK = _assetSink;
  }

  /// @inheritdoc IV3FeeController
  function enableFeeAmount(uint24 fee, int24 tickSpacing) external onlyOwner {
    FACTORY.enableFeeAmount(fee, tickSpacing);
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
    if (FACTORY.feeAmountTickSpacing(feeTier) == 0) revert InvalidFeeTier();
    defaultFees[feeTier] = defaultFeeValue;
  }

  /// @inheritdoc IV3FeeController
  function triggerFeeUpdate(address pool, bytes32[] calldata proof) external {
    bytes32 node = keccak256(abi.encode(pool));
    if (!MerkleProof.verify(proof, merkleRoot, node)) revert InvalidProof();

    _setProtocolFee(pool);
  }

  /// @inheritdoc IV3FeeController
  function setFeeSetter(address newFeeSetter) external onlyOwner {
    feeSetter = newFeeSetter;
  }

  /// @inheritdoc IV3FeeController
  function batchTriggerFeeUpdate(
    address[] calldata pools,
    bytes32[] calldata proof,
    bool[] calldata proofFlags
  ) external {
    bytes32[] memory leaves = new bytes32[](pools.length);
    address pool;
    for (uint256 i; i < pools.length; i++) {
      pool = pools[i];
      leaves[i] = _hash(pool);
      _setProtocolFee(pool);
    }
    if (!MerkleProof.multiProofVerify(proof, proofFlags, merkleRoot, leaves)) revert InvalidProof();
  }

  function _setProtocolFee(address pool) internal {
    uint8 feeValue = defaultFees[IUniswapV3Pool(pool).fee()];
    IUniswapV3PoolOwnerActions(pool).setFeeProtocol(feeValue % 16, feeValue >> 4);
  }

  function _hash(address pool) internal pure returns (bytes32 poolHash) {
    assembly ("memory-safe") {
      mstore(0, and(pool, 0xffffffffffffffffffffffffffffffffffffffff))
      poolHash := keccak256(0, 0x20)
    }
  }
}
