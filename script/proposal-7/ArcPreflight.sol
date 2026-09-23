// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {WormholeChainId} from "govkit/constants/WormholeChainId.sol";
import {WormholeEncoder} from "govkit/bridges/WormholeEncoder.sol";
import {IUniswapV2Factory} from "govkit/interfaces/IUniswapV2Factory.sol";
import {IUniswapV3Factory} from "govkit/interfaces/IUniswapV3Factory.sol";
import {IPoolManager} from "govkit/interfaces/IPoolManager.sol";

import {IUniswapWormholeMessageReceiver} from "./Interfaces.sol";
import "./params/Constants.sol" as Constants;

/// @dev Asserts Arc is ready for fee infrastructure deployment and the proposal's remote calls.
function checkArcPreflight() view {
  Constants.smokeCheck();

  require(block.chainid == Constants.Arc.CHAIN_ID, "not Arc");

  address receiver = Constants.Arc.WORMHOLE_RECEIVER;

  require(
    IUniswapWormholeMessageReceiver(receiver).messageSender()
      == WormholeEncoder.toWormholeFormat(Constants.Ethereum.WORMHOLE_SENDER),
    "receiver.messageSender"
  );
  require(
    IUniswapWormholeMessageReceiver(receiver).ETHEREUM_CHAIN_ID() == WormholeChainId.Ethereum,
    "receiver.ethereumChainId"
  );
  require(
    IUniswapWormholeMessageReceiver(receiver).chainId() == Constants.Arc.WORMHOLE_CHAIN_ID,
    "receiver.chainId"
  );

  require(
    IUniswapV2Factory(Constants.Arc.V2_FACTORY).feeToSetter() == receiver, "v2Factory.feeToSetter"
  );
  require(IUniswapV3Factory(Constants.Arc.V3_FACTORY).owner() == receiver, "v3Factory.owner");
  require(IPoolManager(Constants.Arc.POOL_MANAGER).owner() == receiver, "poolManager.owner");
}
