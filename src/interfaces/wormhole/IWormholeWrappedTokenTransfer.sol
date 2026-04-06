// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

interface IWormholeWrappedTokenTransfer {
  function transferTokens(
    address token,
    uint256 amount,
    uint16 recipientChain,
    bytes32 recipient,
    uint256 arbiterFee,
    uint32 nonce
  ) external payable returns (uint64);
}
