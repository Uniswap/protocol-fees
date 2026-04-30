// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

contract MockEmptyERC20 {
    event MockTransfer(address indexed sender, address indexed receiver, uint256 amount);
    event MockApproval(address indexed owner, address indexed spender, uint256 amount);

    bool public mockShouldThrow;

    function transferFrom(address sender, address receiver, uint256 amount) external returns (bool) {
        require(!mockShouldThrow);

        emit MockTransfer(sender, receiver, amount);

        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        require(!mockShouldThrow);

        emit MockApproval(msg.sender, spender, amount);

        return true;
    }

    function mockSetShouldThrow(bool newMockShouldThrow) external {
        mockShouldThrow = newMockShouldThrow;
    }
}
