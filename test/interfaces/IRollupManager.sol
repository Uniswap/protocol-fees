// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev The RollupManager on Ethereum, which keeps each rollup's last settled local exit root.
interface IRollupManager {
  function rollupCount() external view returns (uint32);
  function getRollupExitRoot() external view returns (bytes32);
  function rollupIDToRollupData(uint32 rollupID)
    external
    view
    returns (
      address rollupContract,
      uint64 chainID,
      address verifier,
      uint64 forkID,
      bytes32 lastLocalExitRoot,
      uint64 lastBatchSequenced,
      uint64 lastVerifiedBatch,
      uint64 legacyLastPendingState,
      uint64 legacyLastPendingStateConsolidated,
      uint64 lastVerifiedBatchBeforeUpgrade,
      uint64 rollupTypeID,
      uint8 rollupVerifierType
    );
}
