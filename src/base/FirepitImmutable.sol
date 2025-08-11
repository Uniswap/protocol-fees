// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {ERC20} from "solmate/src/utils/SafeTransferLib.sol";

abstract contract FirepitImmutable {
  ERC20 public immutable RESOURCE;
  uint256 public immutable THRESHOLD;

  constructor(address _resource, uint256 _threshold) {
    RESOURCE = ERC20(_resource);
    THRESHOLD = _threshold;
  }
}
