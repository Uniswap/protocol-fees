// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IReleaser, Currency} from "../../src/interfaces/IReleaser.sol";

interface IERC20 {
  function approve(address, uint256) external returns (bool);
}

contract MockReleaserCaller {
  event MockReceive(address indexed caller, uint256 indexed amount);

  bool public mockShouldThrow;

  function doApproval(address uni, address spender, uint256 amount) external {
    IERC20(uni).approve(spender, amount);
  }

  function doReleaserCall(
    IReleaser releaser,
    uint256 value,
    uint256 nonce,
    Currency[] calldata assets,
    address receiver
  ) external {
    (bool success,) = payable(address(releaser)).call{value: value}(new bytes(0));

    require(success);

    releaser.release(nonce, assets, receiver);
  }

  receive() external payable {
    require(!mockShouldThrow);

    emit MockReceive(msg.sender, msg.value);
  }

  function mockSetShouldThrow(bool newMockShouldThrow) external {
    mockShouldThrow = newMockShouldThrow;
  }
}
