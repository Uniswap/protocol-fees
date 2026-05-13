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
  uint256 public mockMessageFee;
  uint256 public mockTransceiverCount = 1;

  function transfer(uint256 amount, uint16 recipientChain, bytes32 recipient) external payable {
    require(!mockShouldThrow);

    emit MockTransfer(amount, recipientChain, recipient, msg.sender, msg.value);
  }

  function quoteDeliveryPrice(uint16, bytes memory)
    external
    view
    returns (uint256[] memory, uint256)
  {
    return (new uint256[](0), mockTransceiverCount * mockMessageFee);
  }

  function mockSetShouldThrow(bool newMockShouldThrow) external {
    mockShouldThrow = newMockShouldThrow;
  }

  function mockSetMessageFee(uint256 newMockMessageFee) external {
    mockMessageFee = newMockMessageFee;
  }

  function mockSetTransceiverCount(uint256 newMockTransceiverCount) external {
    mockTransceiverCount = newMockTransceiverCount;
  }
}
