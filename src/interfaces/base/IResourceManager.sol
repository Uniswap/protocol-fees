// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {ERC20} from "solmate/src/utils/SafeTransferLib.sol";

interface IResourceManager {
  function RESOURCE() external view returns (ERC20);
  function RESOURCE_RECIPIENT() external view returns (address);
  function threshold() external view returns (uint256);
  function thresholdSetter() external view returns (address);
  function setThresholdSetter(address newThresholdSetter) external;
}
