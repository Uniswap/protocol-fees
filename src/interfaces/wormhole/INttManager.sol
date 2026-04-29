// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

interface INttManager {
    function transfer(uint256 amount, uint16 recipientChain, bytes32 recipient) external payable;
}
