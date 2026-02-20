// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMessenger {
  function xDomainMessageSender() external view returns (address);
}

/// @title CrossChainAccount
/// @notice L2 contract that receives messages from a specific L1 address via the
///         L2CrossDomainMessenger and forwards them to the destination.
/// @dev Any L2 contract that uses this contract's address as a privileged position
///      (e.g. owner) can be considered to be owned by the `l1Owner`.
///      This is functionally equivalent to the CrossChainAccount contracts already deployed
///      on OP Mainnet (0xa1dD...3518) and Base (0x31FA...6FA9) for the v3 factory.
contract CrossChainAccount {
  IMessenger public immutable messenger;
  address public immutable l1Owner;

  constructor(IMessenger _messenger, address _l1Owner) {
    messenger = _messenger;
    l1Owner = _l1Owner;
  }

  /// @notice Forwards a call to `target` with `data`
  /// @dev Can only be called by the messenger, and only if the L1 message sender is the l1Owner
  function forward(address target, bytes memory data) external {
    require(msg.sender == address(messenger), "Sender is not the messenger");
    require(messenger.xDomainMessageSender() == l1Owner, "L1Sender is not the L1Owner");
    (bool success, bytes memory res) = target.call(data);
    require(success, string(abi.encodePacked("XChain call failed:", res)));
  }
}
