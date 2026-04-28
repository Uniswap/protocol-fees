// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

interface IWormholeRelayer {
  function quoteEVMDeliveryPrice(
    uint16 targetChainId,
    uint256 receiverValue,
    uint256 gasLimit // gas budget for receiveWormholeMessages
  ) external view returns (uint256);
}
