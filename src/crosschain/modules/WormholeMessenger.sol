// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";

interface IWormholeRelayer {
  function sendPayloadToEvm(
    uint16 targetChain,
    address targetAddress,
    bytes calldata payload,
    uint256 value,
    uint32 gasLimit
  ) external payable;
}

contract WormholeMessenger {
  address public immutable MESSENGER;
  address public immutable L2_TARGET;

  constructor(address _messenger, address _l2Target) {
    MESSENGER = _messenger;
    L2_TARGET = _l2Target;
  }

  function messageWormhole(
    uint256 destinationNonce,
    Currency[] memory assets,
    address claimer,
    uint32 l2GasLimit
  ) internal {
    uint256 cost = msg.value;
    // TODO: assert minimum cost?
    uint16 targetChain = 1; // Example chain ID for Wormhole
    IWormholeRelayer(address(0)).sendPayloadToEvm{value: cost}(
      targetChain,
      L2_TARGET,
      abi.encode(destinationNonce, assets, claimer), // Payload contains the message and
        // sender address
      0, // No receiver value needed
      l2GasLimit // Gas limit for the transaction
    );
  }
}
