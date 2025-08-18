// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IL1CrossDomainMessenger} from "../../interfaces/IL1CrossDomainMessenger.sol";
import {UnifiedMessageReceiver} from "../UnifiedMessageReceiver.sol";

abstract contract OPStackMessenger {
  IL1CrossDomainMessenger public immutable messenger;

  constructor(address _messenger) {
    messenger = IL1CrossDomainMessenger(_messenger);
  }

  function _l2Target() internal view virtual returns (address);

  function _messageOP(
    uint256 destinationNonce,
    Currency[] memory assets,
    address claimer,
    uint32 l2GasLimit
  ) internal {
    messenger.sendMessage(
      _l2Target(),
      abi.encodeCall(
        UnifiedMessageReceiver.receiveMessage, (address(this), destinationNonce, assets, claimer)
      ),
      l2GasLimit
    );
  }
}
