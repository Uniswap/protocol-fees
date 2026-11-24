// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev The global exit root manager on X Layer, into which X Layer's updater inserts Ethereum's
/// global exit roots, and to which the unified bridge on X Layer publishes its local exit root.
interface IGlobalExitRootManagerL2 {
  function lastRollupExitRoot() external view returns (bytes32);
  function globalExitRootUpdater() external view returns (address);
  function insertGlobalExitRoot(bytes32 newRoot) external;
}
