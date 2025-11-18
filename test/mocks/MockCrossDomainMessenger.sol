// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IL1CrossDomainMessenger} from "../../src/interfaces/IL1CrossDomainMessenger.sol";

contract MockCrossDomainMessenger is IL1CrossDomainMessenger {
  address public sender;

  function sendMessage(address _target, bytes memory _message, uint32 _gasLimit) external override {
    sender = msg.sender;

    // simulate sending a message
    (bool success,) = _target.call{gas: _gasLimit}(_message);
    require(success, "Message send failed");
  }

  function xDomainMessageSender() external view override returns (address) {
    return sender;
  }
}
