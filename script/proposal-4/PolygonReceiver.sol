// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Constants.sol" as Constants;

contract Receiver {
  function onStateReceive(uint256 id, bytes calldata data) external {
    require(Constants.Polygon.STATE_SYNC == msg.sender);
    require(Constants.L1.GOVERNOR == address(uint160(id)));

    // TODO: take action
  }
}
