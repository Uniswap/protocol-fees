// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IL1CrossDomainMessenger} from "../interfaces/IL1CrossDomainMessenger.sol";
import {IFirepitDestination} from "../interfaces/IFirepitDestination.sol";
import {Nonce} from "../base/Nonce.sol";

contract FirepitSource is Nonce {
  IERC20 public immutable RESOURCE;
  uint256 public immutable THRESHOLD;
  IL1CrossDomainMessenger public immutable MESSENGER;
  address public immutable L2_TARGET;

  constructor(address _resource, uint256 _threshold, address _messenger, address _l2Target) {
    RESOURCE = IERC20(_resource);
    THRESHOLD = _threshold;
    MESSENGER = IL1CrossDomainMessenger(_messenger);
    L2_TARGET = _l2Target;
  }

  /// @notice Torches the RESOURCE by sending it to the burn address and sends a cross-domain
  /// message to release the assets
  function torch(uint256 _nonce, Currency[] memory assets, address claimer, uint32 l2GasLimit)
    external
    checkNonce(_nonce)
  {
    uint256 deadline = block.timestamp + 30 minutes;

    // In the event of a cancelled / faulty message, ensure the RESOURCE is recoverable
    // therefore, only transfer the resource to the contract
    RESOURCE.transferFrom(msg.sender, address(this), THRESHOLD);

    // Calls Releaser.torch(assets, claimer) on L2
    MESSENGER.sendMessage(
      L2_TARGET,
      abi.encodeCall(IFirepitDestination.claimTo, (assets, claimer, deadline)),
      l2GasLimit
    );
  }

  // TODO: resource recovery for failed messages
}
