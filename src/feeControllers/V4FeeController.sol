// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {MerkleProof} from "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

/// @title V4FeeController
/// @notice Triggers the collection of protocol fees to a predefined fee sink.
contract V4FeeController is Owned {
  /// @notice Thrown when the amount collected is less than the amount expected.
  error AmountCollectedTooLow(uint256 amountCollected, uint256 amountExpected);

  /// @notice Thrown when the merkle proof is invalid.
  error InvalidProof();

  IPoolManager public immutable POOL_MANAGER;

  address public feeSink;

  bytes32 public merkleRoot;

  constructor(address _poolManager, address _feeSink, address _owner) Owned(_owner) {
    POOL_MANAGER = IPoolManager(_poolManager);
    feeSink = _feeSink;
  }

  /// @notice Collects the protocol fees for the given currencies to the fee sink.
  /// @param currency The currencies to collect fees for.
  /// @param amountRequested The amount of each currency to request.
  /// @param amountExpected The amount of each currency that is expected to be collected.
  function collect(
    Currency[] memory currency,
    uint256[] memory amountRequested,
    uint256[] memory amountExpected
  ) external {
    uint256 amountCollected;
    for (uint256 i = 0; i < currency.length; i++) {
      uint256 _amountRequested = amountRequested[i];
      uint256 _amountExpected = amountExpected[i];

      amountCollected = POOL_MANAGER.collectProtocolFees(feeSink, currency[i], _amountRequested);
      if (amountCollected < _amountExpected) {
        revert AmountCollectedTooLow(amountCollected, _amountExpected);
      }
    }
  }

  /// @notice Sets the merkle root for the fee controller.
  /// @dev only callable by owner
  /// @param _merkleRoot The merkle root to set.
  function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
    merkleRoot = _merkleRoot;
  }

  /// @notice Triggers the fee update for the given pool key.
  /// @param _poolKey The pool key to update the fee for.
  /// @param newProtocolFee The new protocol fee to set.
  /// @param proof The merkle proof corresponding to the set merkle root. Merkle root is generated
  /// from leaves of keccak256(abi.encode(poolKey, protocolFee)).
  function triggerFeeUpdate(
    PoolKey calldata _poolKey,
    uint24 newProtocolFee,
    bytes32[] memory proof
  ) external {
    bytes32 node = keccak256(abi.encode(_poolKey, newProtocolFee));
    if (!MerkleProof.verify(proof, merkleRoot, node)) revert InvalidProof();

    POOL_MANAGER.setProtocolFee(_poolKey, newProtocolFee);
  }
}
