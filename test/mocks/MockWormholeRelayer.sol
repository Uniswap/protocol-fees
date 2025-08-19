// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IWormholeReceiver} from "../../src/interfaces/external/IWormholeReceiver.sol";

contract MockWormholeRelayer {
  function quoteEVMDeliveryPrice(
    uint16, // targetChain
    uint256, // receiverValue
    uint256 l2GasLimit
  ) external pure returns (uint256, uint256) {
    // Mock implementation: return a fixed price based on the gas limit
    return (uint256(l2GasLimit) * 1000, 0); // Example: 1000 wei per gas unit
  }

  function sendPayloadToEvm(
    uint16, // targetChain
    address targetAddress,
    bytes memory payload,
    uint256 receiverValue,
    uint256 l2GasLimit
  ) external payable {
    bytes[] memory vaas;
    uint16 sourceChain;
    bytes32 deliveryHash;
    IWormholeReceiver(targetAddress).receiveWormholeMessages{gas: l2GasLimit, value: receiverValue}(
      payload, vaas, bytes32(uint256(uint160(msg.sender))), sourceChain, deliveryHash
    );
  }
}
