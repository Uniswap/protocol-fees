// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @dev `StablePairHook`'s per-pool fee config. The hook replaces the whole struct on update.
struct StableFeeConfig {
  uint24 k;
  uint24 optimalFeeE6;
  uint8 targetMultiplier;
  uint160 referenceSqrtPriceX96;
}

/// @dev The parts of `StablePairHook` this proposal reads and calls. The hook takes v4's
/// `PoolId`, which ABI-encodes as `bytes32`.
interface IStablePairHook {
  function batchUpdateFeeConfig(bytes32[] calldata poolIds, StableFeeConfig[] calldata feeConfigs)
    external;
  function feeConfig(bytes32 poolId)
    external
    view
    returns (uint24 k, uint24 optimalFeeE6, uint8 targetMultiplier, uint160 referenceSqrtPriceX96);
  function hasRole(bytes32 role, address account) external view returns (bool);
  function CONFIG_MANAGER_ROLE() external view returns (bytes32);
}

/// @dev The part of Arbitrum's Bridge on Ethereum the preflight reads: the rollup the Bridge
/// delivers the Inbox's messages to.
interface IArbitrumBridge {
  function rollup() external view returns (address);
}

/// @dev The part of an Arbitrum rollup on Ethereum the preflight reads: the chain the rollup runs.
interface IArbitrumRollup {
  function chainId() external view returns (uint256);
}
