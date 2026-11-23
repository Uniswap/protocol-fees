// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IXLayerBridge} from "../../src/interfaces/external/IXLayerBridge.sol";

/// @dev The unified bridge, on Ethereum and on X Layer, with the functions tests call that
/// `IXLayerBridge` does not expose.
interface IXLayerBridgeFull is IXLayerBridge {
  /// @dev Emitted when the bridge pays out a claimed deposit.
  event ClaimEvent(
    uint256 globalIndex,
    uint32 originNetwork,
    address originAddress,
    address destinationAddress,
    uint256 amount
  );

  function depositCount() external view returns (uint256);
  function getRoot() external view returns (bytes32);
  function globalExitRootManager() external view returns (address);

  function getLeafValue(
    uint8 leafType,
    uint32 originNetwork,
    address originAddress,
    uint32 destinationNetwork,
    address destinationAddress,
    uint256 amount,
    bytes32 metadataHash
  ) external pure returns (bytes32);

  function calculateRoot(bytes32 leafHash, bytes32[32] calldata smtProof, uint32 index)
    external
    pure
    returns (bytes32);

  function claimAsset(
    bytes32[32] calldata smtProofLocalExitRoot,
    bytes32[32] calldata smtProofRollupExitRoot,
    uint256 globalIndex,
    bytes32 mainnetExitRoot,
    bytes32 rollupExitRoot,
    uint32 originNetwork,
    address originTokenAddress,
    uint32 destinationNetwork,
    address destinationAddress,
    uint256 amount,
    bytes calldata metadata
  ) external;
}
