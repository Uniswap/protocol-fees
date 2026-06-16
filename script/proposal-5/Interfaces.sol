// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IOmnichainProposalSender {
  function execute(uint16 remoteChainId, bytes calldata payload, bytes calldata adapterParams)
    external
    payable;

  function setTrustedRemoteAddress(uint16 remoteChainId, bytes calldata remoteAddress) external;
}
