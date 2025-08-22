// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Owned} from "solmate/src/auth/Owned.sol";
import {ERC20} from "solmate/src/utils/SafeTransferLib.sol";

abstract contract FirepitImmutable is Owned {
  ERC20 public immutable RESOURCE;
  uint256 public threshold;

  constructor(address _resource, uint256 _threshold, address _owner) Owned(_owner) {
    RESOURCE = ERC20(_resource);
    threshold = _threshold;
  }

  function setThreshold(uint256 _threshold) external onlyOwner {
    threshold = _threshold;
  }
}
