// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Owned} from "solmate/src/auth/Owned.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IFirepitDestination} from "../interfaces/IFirepitDestination.sol";

contract UnifiedMessageReceiver is Owned {
  IFirepitDestination public firepitDestination;

  address public allowableSource;

  /// @dev Owner is expected to update to accept new bridge adapters
  mapping(address callers => bool allowed) public allowableCallers;

  constructor(address _owner) Owned(_owner) {}

  modifier allowed(address source) {
    require(allowableSource == source, "Caller not allowed");
    require(allowableCallers[msg.sender], "Caller not allowed");
    _;
  }

  function receiveMessage(
    address sourceContract,
    uint256 destinationNonce,
    Currency[] memory assets,
    address claimer
  ) external allowed(sourceContract) {
    firepitDestination.claimTo(destinationNonce, assets, claimer);
  }

  function setFirepitDestination(address _newDestination) external onlyOwner {
    firepitDestination = IFirepitDestination(_newDestination);
  }

  function setAllowableSource(address source) external onlyOwner {
    allowableSource = source;
  }

  function setAllowableCaller(address caller, bool isAllowed) external onlyOwner {
    allowableCallers[caller] = isAllowed;
  }
}
