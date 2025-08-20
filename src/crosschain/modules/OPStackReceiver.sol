// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IL1CrossDomainMessenger} from "../../interfaces/IL1CrossDomainMessenger.sol";
import {UnifiedMessageReceiver} from "../UnifiedMessageReceiver.sol";

contract OPStackReceiver {
  IL1CrossDomainMessenger public immutable MESSENGER;
  UnifiedMessageReceiver public immutable UNIFIED_MESSAGE_RECEIVER;

  constructor(address _messenger, address _unifiedMessageReceiver) {
    MESSENGER = IL1CrossDomainMessenger(_messenger);
    UNIFIED_MESSAGE_RECEIVER = UnifiedMessageReceiver(_unifiedMessageReceiver);
  }

  function receiveAndForward(uint256 destinationNonce, Currency[] memory assets, address claimer)
    external
  {
    UNIFIED_MESSAGE_RECEIVER.receiveMessage(
      MESSENGER.xDomainMessageSender(), destinationNonce, assets, claimer
    );
  }
}
