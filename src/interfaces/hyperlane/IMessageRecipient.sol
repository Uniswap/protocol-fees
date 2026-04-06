// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

interface IMessageRecipient {
    function handle(
        uint32 origin,
        bytes32 sender,
        bytes calldata body
    ) external payable;
}
