// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

contract MockNttManager {
    event MockTransfer(
        uint256 indexed amount,
        uint16 indexed recipientChain,
        bytes32 indexed recipient,
        address caller,
        uint256 value
    );

    bool public mockShouldThrow;

    function transfer(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient
    ) external payable {
        require(!mockShouldThrow);

        emit MockTransfer(amount, recipientChain, recipient, msg.sender, msg.value);
    }

    function mockSetShouldThrow(bool newMockShouldThrow) external {
        mockShouldThrow = newMockShouldThrow;
    }

}
