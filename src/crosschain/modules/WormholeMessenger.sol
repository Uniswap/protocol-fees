// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IWormholeRelayer} from "../../interfaces/external/IWormholeRelayer.sol";

abstract contract WormholeMessenger {
  IWormholeRelayer public immutable WORMHOLE_RELAYER;
  address public immutable WORMHOLE_RECEIVER;

  /// @dev thrown when the caller does not provide enough gas for Wormhole
  error InsufficientGas();

  constructor(address _wormholeRelayer, address _wormholeReceiver) {
    WORMHOLE_RELAYER = IWormholeRelayer(_wormholeRelayer);
    WORMHOLE_RECEIVER = _wormholeReceiver;
  }

  function _messageWormhole(
    uint256 destinationNonce,
    Currency[] memory assets,
    address claimer,
    uint32 l2GasLimit,
    uint16 targetChain
  ) internal {
    uint256 cost = msg.value;
    (uint256 quote,) = WORMHOLE_RELAYER.quoteEVMDeliveryPrice(targetChain, 0, l2GasLimit);
    require(cost >= quote, InsufficientGas());

    WORMHOLE_RELAYER.sendPayloadToEvm{value: quote}(
      targetChain,
      WORMHOLE_RECEIVER,
      abi.encode(destinationNonce, assets, claimer),
      0, // No receiver value needed
      l2GasLimit // Gas limit for the transaction
    );
  }
}
