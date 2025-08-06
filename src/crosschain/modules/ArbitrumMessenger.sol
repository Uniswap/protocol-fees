// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IFirepitDestination} from "../../interfaces/IFirepitDestination.sol";

interface IInbox {
  function createRetryableTicket(
    address to,
    uint256 l2CallValue,
    uint256 maxSubmissionCost,
    address excessFeeRefundAddress,
    address callValueRefundAddress,
    uint256 gasLimit,
    uint256 maxFeePerGas,
    bytes calldata data
  ) external payable returns (uint256);
}

contract ArbitrumMessenger {
  address public immutable MESSENGER;
  address public immutable L2_TARGET;

  constructor(address _messenger, address _l2Target) {
    MESSENGER = _messenger;
    L2_TARGET = _l2Target;
  }

  function messageArbitrum(
    uint256 destinationNonce,
    Currency[] memory assets,
    address claimer,
    uint32 l2GasLimit
  ) internal {
    uint256 maxSubmissionCost = 0; // Set to zero if not needed
    uint256 gasPriceBid = 0; // Set to zero if not needed

    // Chain uses ETH as the gas token
    uint256 ticketID = IInbox(MESSENGER).createRetryableTicket{value: msg.value}(
      L2_TARGET,
      0,
      maxSubmissionCost,
      msg.sender,
      msg.sender,
      l2GasLimit,
      gasPriceBid,
      abi.encodeWithSelector(
        IFirepitDestination.claimTo.selector, destinationNonce, assets, claimer
      )
    );
  }
}
