// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {FirepitSource} from "./FirepitSource.sol";
import {OPStackMessenger} from "./modules/OPStackMessenger.sol";
import {WormholeMessenger} from "./modules/WormholeMessenger.sol";

contract DemoFirepitSource is FirepitSource, OPStackMessenger, WormholeMessenger {
  address public immutable L2_TARGET;

  constructor(
    address _resource,
    uint256 _threshold,
    address l2Target_,
    address _opMessenger,
    address _wormhole
  )
    FirepitSource(_resource, _threshold)
    OPStackMessenger(_opMessenger)
    WormholeMessenger(_wormhole)
  {
    L2_TARGET = l2Target_;
  }

  function _l2Target()
    internal
    view
    override(OPStackMessenger, WormholeMessenger)
    returns (address)
  {
    return L2_TARGET;
  }

  function _sendReleaseMessage(
    uint256 bridgeId,
    uint256 destinationNonce,
    Currency[] memory assets,
    address claimer,
    bytes memory addtlData
  ) internal override {
    if (bridgeId == 0) {
      (uint32 l2GasLimit) = abi.decode(addtlData, (uint32));
      _messageOP(destinationNonce, assets, claimer, l2GasLimit);
    } else if (bridgeId == 1) {
      (uint32 l2GasLimit, uint16 targetChain) = abi.decode(addtlData, (uint32, uint16));
      _messageWormhole(destinationNonce, assets, claimer, l2GasLimit, targetChain);
    } else {
      revert("Unsupported bridge ID");
    }
  }
}
