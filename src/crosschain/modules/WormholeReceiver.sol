// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IWormholeReceiver} from "../../interfaces/external/IWormholeReceiver.sol";

contract WormholeReceiver is IWormholeReceiver {
  function _validateOrigins(address source, address caller) internal virtual {}

  function _claimTo(uint256 destinationNonce, Currency[] memory assets, address recipient)
    internal
    virtual
  {}

  /// @inheritdoc IWormholeReceiver
  function receiveWormholeMessages(
    bytes memory payload,
    bytes[] memory, // additional VAAs (optional, not needed here)
    bytes32 sourceAddress,
    uint16, // source chain
    bytes32 // delivery hash
  ) external payable {
    _validateOrigins(address(uint160(uint256(sourceAddress))), msg.sender);

    // Decode the payload to extract the message
    (uint256 nonce, Currency[] memory assets, address recipient) =
      abi.decode(payload, (uint256, Currency[], address));
    _claimTo(nonce, assets, recipient);
  }
}
