// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Uniswap} from "govkit/types/Uniswap.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {InboxEncoder} from "govkit/bridges/InboxEncoder.sol";

import {Arc} from "../../proposal-7/params/Constants.sol";

/// @notice Uniswap's v4 accounts on one chain.
struct V4Accounts {
  /// @dev The v4 PoolManager.
  address poolManager;
  /// @dev The account that the Timelock's calls to the chain run as. It owns the PoolManager, and
  ///      the prerequisite scripts make it the owner and fee setter of each contract they deploy.
  address governanceExecutor;
}

/// @notice Returns Uniswap's v4 accounts on `chainId`, for the 13 chains proposals 104 and 105
///         configure.
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
