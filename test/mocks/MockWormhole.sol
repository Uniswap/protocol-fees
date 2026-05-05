// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IWormhole} from "../../src/interfaces/wormhole/IWormhole.sol";

contract MockWormhole is IWormhole {
  event MockPublishMessage(uint32 indexed nonce, uint8 indexed consistencyLevel, bytes payload);

  uint64 internal _sequence;

  bool public mockShouldThrow;

  uint256 public messageFee;

  function publishMessage(uint32 nonce, bytes memory payload, uint8 consistencyLevel)
    external
    payable
    returns (uint64 sequence)
  {
    require(!mockShouldThrow);

    _sequence + 1;
    sequence = _sequence;

    emit MockPublishMessage(nonce, consistencyLevel, payload);
  }

  function mockSetMessageFee(uint256 newMessageFee) external {
    messageFee = newMessageFee;
  }

  function mockSetShouldThrow(bool newMockShouldThrow) external {
    mockShouldThrow = newMockShouldThrow;
  }
}
