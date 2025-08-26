// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {SafeTransferLib, ERC20} from "solmate/src/utils/SafeTransferLib.sol";
import {IL1CrossDomainMessenger} from "../interfaces/IL1CrossDomainMessenger.sol";
import {IFirepitDestination} from "../interfaces/IFirepitDestination.sol";
import {Nonce} from "../base/Nonce.sol";
import {FirepitImmutable} from "../base/FirepitImmutable.sol";

abstract contract FirepitSource is FirepitImmutable, Nonce {
  using SafeTransferLib for ERC20;

  uint256 public constant DEFAULT_BRIDGE_ID = 0;

  constructor(address _owner, address _thresholdSetter, address _resource, uint256 _threshold)
    FirepitImmutable(_resource, _threshold, _owner, _thresholdSetter)
  {}

  function _sendReleaseMessage(
    uint256 bridgeId,
    uint256 destinationNonce,
    Currency[] memory assets,
    address claimer,
    bytes memory addtlData
  ) internal virtual;

  /// @notice Torches the RESOURCE by sending it to the burn address and sends a cross-domain
  /// message to release the assets
  function torch(uint256 _nonce, Currency[] memory assets, address claimer, uint32 l2GasLimit)
    external
    handleNonce(_nonce)
  {
    RESOURCE.safeTransferFrom(msg.sender, address(0), threshold);

    _sendReleaseMessage(DEFAULT_BRIDGE_ID, _nonce, assets, claimer, abi.encode(l2GasLimit));
  }
}
