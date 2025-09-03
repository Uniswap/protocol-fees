// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Owned} from "solmate/src/auth/Owned.sol";
import {ERC20} from "solmate/src/utils/SafeTransferLib.sol";

abstract contract FirepitImmutable is Owned {
  uint256 public threshold;
  address public thresholdSetter;
  ERC20 public immutable RESOURCE;

  modifier onlyThresholdSetter() {
    require(msg.sender == thresholdSetter, "UNAUTHORIZED");
    _;
  }

  constructor(address _resource, uint256 _threshold, address _owner, address _thresholdSetter)
    Owned(_owner)
  {
    RESOURCE = ERC20(_resource);
    threshold = _threshold;
    thresholdSetter = _thresholdSetter;
  }

  function setThresholdSetter(address _thresholdSetter) external onlyOwner {
    thresholdSetter = _thresholdSetter;
  }

  function setThreshold(uint256 _threshold) external onlyThresholdSetter {
    threshold = _threshold;
  }
}
