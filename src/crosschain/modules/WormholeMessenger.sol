// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IWormholeRelayer} from "../../interfaces/external/IWormholeRelayer.sol";

abstract contract WormholeMessenger {
  IWormholeRelayer public immutable wormholeRelayer;

  constructor(address _wormholeRelayer) {
    wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
  }

  function _l2Target() internal view virtual returns (address);

  function _messageWormhole(
    uint256 destinationNonce,
    Currency[] memory assets,
    address claimer,
    uint32 l2GasLimit,
    uint16 targetChain
  ) internal {
    uint256 cost = msg.value;
    (uint256 quote,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, l2GasLimit);
    require(cost >= quote, "Insufficient funds");

    wormholeRelayer.sendPayloadToEvm{value: quote}(
      targetChain,
      _l2Target(),
      abi.encode(destinationNonce, assets, claimer), // Payload contains the message and sender
        // address
      0, // No receiver value needed
      l2GasLimit // Gas limit for the transaction
    );
  }
}
