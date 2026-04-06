// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

interface IMailbox {
    function dispatch(
        uint32 destDomain,
        bytes32 receiverAddress,
        bytes calldata msgBody
    ) external payable returns (bytes32 messageId);

    function quoteDispatch(
        uint32 destDomain,
        bytes32 receiverAddress,
        bytes calldata msgBody
    ) external view returns (uint256);

    function localDomain() external view returns (uint32);
}
