// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IL1CrossDomainMessenger} from "../../interfaces/IL1CrossDomainMessenger.sol";
import {IFirepitDestination} from "../../interfaces/IFirepitDestination.sol";
import {UnifiedMessageReceiver} from "../UnifiedMessageReceiver.sol";

contract OPStackReceiver {
  IL1CrossDomainMessenger public immutable messenger;
  UnifiedMessageReceiver public immutable unifiedMessageReceiver;

  constructor(address _messenger, address _unifiedMessageReceiver) {
    messenger = IL1CrossDomainMessenger(_messenger);
    unifiedMessageReceiver = UnifiedMessageReceiver(_unifiedMessageReceiver);
  }

  function receiveAndForward(uint256 destinationNonce, Currency[] memory assets, address claimer)
    external
  {
    unifiedMessageReceiver.receiveMessage(
      messenger.xDomainMessageSender(), destinationNonce, assets, claimer
    );
  }
}
