// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev The global exit root manager on Ethereum. The unified bridge updates its mainnet exit root
/// on a deposit, and the RollupManager updates its rollup exit root when a rollup settles.
interface IGlobalExitRootManagerL1 {
  function rollupManager() external view returns (address);
  function lastMainnetExitRoot() external view returns (bytes32);
  function lastRollupExitRoot() external view returns (bytes32);
  function globalExitRootMap(bytes32 globalExitRoot) external view returns (uint256);
  function updateExitRoot(bytes32 newRoot) external;
}
