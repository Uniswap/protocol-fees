// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

interface IL1CrossDomainMessenger {
  function sendMessage(address _target, bytes calldata _message, uint32 _minGasLimit) external;
  function xDomainMessageSender() external view returns (address);
}
