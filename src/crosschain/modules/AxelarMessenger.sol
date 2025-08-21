// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IAxelarGateway} from "axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";
import {Currency} from "v4-core/types/Currency.sol";

/**
 * @title AxelarMessenger
 * @notice Send a message from chain A to chain B and stores gmp message
 */
contract AxelarMessenger {
  string destinationChain;
  string destinationAddress;
  IAxelarGateway public immutable gateway;
  IAxelarGasService public immutable gasService;

  constructor(
    address _gateway,
    address _gasReceiver,
    string memory _destinationChain,
    string memory _destinationAddress
  ) {
    gateway = IAxelarGateway(_gateway);
    gasService = IAxelarGasService(_gasReceiver);
    destinationChain = _destinationChain;
    destinationAddress = _destinationAddress;
  }

  function sendAxelarMessage(
    uint256 destinationNonce,
    Currency[] memory assets,
    address claimer,
    bytes memory addtlData
  ) external payable {
    require(msg.value > 0, "Gas payment is required");

    bytes memory payload = abi.encode(destinationNonce, assets, claimer);

    gasService.payNativeGasForContractCall{value: msg.value}(
      address(this), destinationChain, destinationAddress, payload, msg.sender
    );
    gateway.callContract(destinationChain, destinationAddress, payload);
  }
}
