// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Constants.sol" as Constants;

/// @title Polygon Message Sender
/// @dev For Ethereum -> Polygon
/// @dev Data is sent by logging
contract PolygonSender {
  /// @notice Picked up by Polygon nodes
  /// @param id Caller contract's ID (address)
  /// @param target Target contract address
  /// @param data Data to send to target.
  event StateSynced(uint256 indexed id, address indexed target, bytes data);

  /// @notice Logs `StateSynced` which Polygon nodes forward.
  /// @dev TODO: figure out how to price execution cost?
  function sendIt(address target, bytes calldata data) external {
    require(msg.sender == Constants.L1.GOVERNOR);

    emit StateSynced(uint160(address(this)), target, data);
  }
}
