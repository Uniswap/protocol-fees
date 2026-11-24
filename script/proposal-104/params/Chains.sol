// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Uniswap} from "govkit/types/Uniswap.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {InboxEncoder} from "govkit/bridges/InboxEncoder.sol";
import {Vm} from "forge-std/Vm.sol";

import {Arc} from "../../proposal-7/params/Constants.sol";

/// @dev Foundry's cheatcode contract, at the address forge-std's `Base` gives it. govkit's `vm`
///      is `VmSafe`, which cannot fork.
Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

/// @notice Uniswap's v4 accounts on a given chain.
struct V4Accounts {
  /// @dev The v4 PoolManager.
  address poolManager;
  /// @dev Governance's avatar. It owns the PoolManager and will be set as the owner
  ///      of the contracts deployed by the prerequisite scripts.
  address governanceExecutor;
}

/// @notice Returns Uniswap's v4 accounts on `chainId`, for the 13 chains configured by
///         proposals 104 and 105.
/// @dev Reverts for any other chain.
function v4Accounts(Uniswap storage uniswap, uint256 chainId) view returns (V4Accounts memory) {
  // Proposal 104
  if (chainId == ChainId.Ethereum) {
    return V4Accounts(uniswap.ethereum.poolManager, uniswap.ethereum.timelock);
  }
  if (chainId == ChainId.Arbitrum) {
    return
      V4Accounts(
        uniswap.arbitrum.poolManager, InboxEncoder.arbitrumAlias(uniswap.ethereum.timelock)
      );
  }
  if (chainId == ChainId.Base) {
    return V4Accounts(uniswap.base.poolManager, uniswap.base.crossChainAccount);
  }
  if (chainId == ChainId.Optimism) {
    return V4Accounts(uniswap.optimism.poolManager, uniswap.optimism.crossChainAccount);
  }
  if (chainId == ChainId.BNBChain) {
    return V4Accounts(uniswap.bnbChain.poolManager, uniswap.bnbChain.wormholeReceiver);
  }
  if (chainId == ChainId.Polygon) {
    return V4Accounts(uniswap.polygon.poolManager, uniswap.polygon.fxReceiver);
  }
  if (chainId == ChainId.Robinhood) {
    return V4Accounts(
      uniswap.robinhood.poolManager, InboxEncoder.arbitrumAlias(uniswap.ethereum.timelock)
    );
  }
  if (chainId == Arc.CHAIN_ID) return V4Accounts(Arc.POOL_MANAGER, Arc.WORMHOLE_RECEIVER);

  // Proposal 105
  if (chainId == ChainId.Celo) {
    return V4Accounts(uniswap.celo.poolManager, uniswap.celo.crossChainAccount);
  }
  if (chainId == ChainId.Soneium) {
    return V4Accounts(uniswap.soneium.poolManager, uniswap.soneium.crossChainAccount);
  }
  if (chainId == ChainId.WorldChain) {
    return V4Accounts(uniswap.worldChain.poolManager, uniswap.worldChain.crossChainAccount);
  }
  if (chainId == ChainId.XLayer) {
    return V4Accounts(uniswap.xLayer.poolManager, uniswap.xLayer.crossChainAccount);
  }
  if (chainId == ChainId.Zora) {
    return V4Accounts(uniswap.zora.poolManager, uniswap.zora.crossChainAccount);
  }
  revert("no v4 accounts for chain");
}

/// @notice Returns the `foundry.toml` RPC alias of `chainId`, for the 13 chains configured by
///         proposals 104 and 105.
/// @dev Reverts for any other chain.
function rpcAlias(uint256 chainId) pure returns (string memory) {
  if (chainId == ChainId.Ethereum) return "mainnet";
  if (chainId == ChainId.Arbitrum) return "arbitrum";
  if (chainId == ChainId.Base) return "base";
  if (chainId == ChainId.Optimism) return "optimism";
  if (chainId == ChainId.BNBChain) return "bnb_chain";
  if (chainId == ChainId.Polygon) return "polygon";
  if (chainId == ChainId.Robinhood) return "robinhood";
  if (chainId == Arc.CHAIN_ID) return "arc";
  if (chainId == ChainId.Celo) return "celo";
  if (chainId == ChainId.Soneium) return "soneium";
  if (chainId == ChainId.XLayer) return "xlayer";
  if (chainId == ChainId.WorldChain) return "world_chain";
  if (chainId == ChainId.Zora) return "zora";
  revert("no RPC alias for chain");
}

/// @notice Forks `chainId` at its latest block through its `foundry.toml` RPC alias and selects
///         the fork.
/// @dev Reverts if the alias reaches another chain, so a misconfigured RPC URL cannot make a
///      multi-chain check skip `chainId`.
function selectChain(uint256 chainId) {
  vm.createSelectFork(rpcAlias(chainId));
  require(
    block.chainid == chainId,
    string.concat("RPC alias ", rpcAlias(chainId), " reaches another chain")
  );
}
