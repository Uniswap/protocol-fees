// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

abstract contract FirepitImmutable {
  IERC20 public immutable RESOURCE;
  uint256 public immutable THRESHOLD;

  constructor(address _resource, uint256 _threshold) {
    RESOURCE = IERC20(_resource);
    THRESHOLD = _threshold;
  }
}
