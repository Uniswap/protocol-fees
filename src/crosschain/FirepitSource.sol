// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IL1CrossDomainMessenger} from "../interfaces/IL1CrossDomainMessenger.sol";
import {IFirepitDestination} from "../interfaces/IFirepitDestination.sol";
import {Nonce} from "../base/Nonce.sol";
import {FirepitImmutable} from "../base/FirepitImmutable.sol";

abstract contract FirepitSource is FirepitImmutable, Nonce {
  uint256 public constant DEFAULT_BRIDGE_ID = 0;

  constructor(address _resource, uint256 _threshold) FirepitImmutable(_resource, _threshold) {}

  function _sendReleaseMessage(
    uint256 bridgeId,
    uint256 destinationNonce,
    Currency[] memory assets,
    address claimer,
    uint256 deadline,
    bytes memory addtlData
  ) internal virtual;

  /// TODO: DRAFT
  // function replayTorch(
  //   uint256 bridgeId,
  //   uint256 destinationNonce,
  //   Currency[] memory assets,
  //   address claimer,
  //   uint32 l2GasLimit
  // ) external {
  //   require(nonceOwners[destinationNonce] == msg.sender, "Not the nonce owner");
  //   _sendReleaseMessage(
  //     bridgeId,
  //     nonce = 100, // current value is 101, but pass 100 ??
  //     assets,
  //     claimer,
  //     block.timestamp + 30 minutes,
  //     abi.encode(l2GasLimit)
  //   );
  // }

  /// @notice Torches the RESOURCE by sending it to the burn address and sends a cross-domain
  /// message to release the assets
  function torch(uint256 _nonce, Currency[] memory assets, address claimer, uint32 l2GasLimit)
    external
    handleNonce(_nonce)
  {
    uint256 deadline = block.timestamp + 30 minutes; // TODO: specify a value

    // In the event of a cancelled / faulty message, ensure the RESOURCE is recoverable
    // therefore, only transfer the resource to the contract
    RESOURCE.transferFrom(msg.sender, address(0), THRESHOLD);

    _sendReleaseMessage(
      DEFAULT_BRIDGE_ID, _nonce, assets, claimer, deadline, abi.encode(l2GasLimit)
    );
  }
}
