// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IL1CrossDomainMessenger} from "../interfaces/IL1CrossDomainMessenger.sol";
import {IFirepitDestination} from "../interfaces/IFirepitDestination.sol";
import {FirepitSource} from "./FirepitSource.sol";

contract OPStackFirepitSource is FirepitSource {
  IL1CrossDomainMessenger public immutable MESSENGER;
  address public immutable L2_TARGET;

  constructor(address _resource, address _messenger, address _l2Target)
    FirepitSource(msg.sender, _resource)
  {
    MESSENGER = IL1CrossDomainMessenger(_messenger);
    L2_TARGET = _l2Target;
  }

  function _sendReleaseMessage(
    uint256, // bridgeId
    uint256 destinationNonce,
    Currency[] memory assets,
    address claimer,
    bytes memory addtlData
  ) internal override {
    (uint32 l2GasLimit) = abi.decode(addtlData, (uint32));
    MESSENGER.sendMessage(
      L2_TARGET,
      abi.encodeCall(IFirepitDestination.claimTo, (destinationNonce, assets, claimer)),
      l2GasLimit
    );
  }
}
