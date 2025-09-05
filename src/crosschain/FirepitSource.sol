// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {SafeTransferLib, ERC20} from "solmate/src/utils/SafeTransferLib.sol";
import {Nonce} from "../base/Nonce.sol";
import {ResourceManager} from "../base/ResourceManager.sol";

abstract contract FirepitSource is ResourceManager, Nonce {
  using SafeTransferLib for ERC20;

  uint256 public constant DEFAULT_BRIDGE_ID = 0;

  /// TODO: Move threshold to constructor. It should not default to 0.
  constructor(address _owner, address _resource)
    ResourceManager(_resource, 69_420, _owner, address(0xdead))
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
  function release(uint256 _nonce, Currency[] memory assets, address claimer, uint32 l2GasLimit)
    external
    handleNonce(_nonce)
  {
    RESOURCE.safeTransferFrom(msg.sender, RESOURCE_RECIPIENT, threshold);

    _sendReleaseMessage(DEFAULT_BRIDGE_ID, _nonce, assets, claimer, abi.encode(l2GasLimit));
  }
}
