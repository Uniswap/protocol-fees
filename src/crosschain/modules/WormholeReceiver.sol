// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IWormholeReceiver} from "../../interfaces/external/IWormholeReceiver.sol";
import {UnifiedMessageReceiver} from "../UnifiedMessageReceiver.sol";

contract WormholeReceiver is IWormholeReceiver {
  address public immutable wormholeRelayer;
  UnifiedMessageReceiver public immutable unifiedMessageReceiver;

  constructor(address _wormhole, address _unifiedMessageReceiver) {
    wormholeRelayer = _wormhole;
    unifiedMessageReceiver = UnifiedMessageReceiver(_unifiedMessageReceiver);
  }

  /// @inheritdoc IWormholeReceiver
  function receiveWormholeMessages(
    bytes memory payload,
    bytes[] memory, // additional VAAs (optional, not needed here)
    bytes32 sourceAddress,
    uint16, // source chain
    bytes32 // delivery hash
  ) external payable {
    // receive messages only from wormhole
    require(msg.sender == wormholeRelayer, "Unauthorized sender");

    // Decode the payload to extract the message
    (uint256 nonce, Currency[] memory assets, address recipient) =
      abi.decode(payload, (uint256, Currency[], address));
    unifiedMessageReceiver.receiveMessage(
      address(uint160(uint256(sourceAddress))), nonce, assets, recipient
    );
  }
}
