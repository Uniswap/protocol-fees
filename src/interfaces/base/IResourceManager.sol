// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {ERC20} from "solmate/src/utils/SafeTransferLib.sol";

/// @title Resource Manager Interface
/// @notice The interface for managing the resource token and its threshold value
interface IResourceManager {
  /// @notice Thrown when an unauthorized address attempts to call a restricted function
  error Unauthorized();

  /// @notice The resource token required by parent IReleaser
  function RESOURCE() external view returns (ERC20);

  /// @notice The recipient of the `RESOURCE` tokens
  function RESOURCE_RECIPIENT() external view returns (address);

  /// @notice The minimum threshold of `RESOURCE` tokens required to perform a release
  function threshold() external view returns (uint256);

  /// @notice The address authorized to set the `threshold` value
  function thresholdSetter() external view returns (address);

  /// @notice Set the address authorized to set the `threshold` value
  /// @dev only callable by `owner`
  function setThresholdSetter(address newThresholdSetter) external;

  /// @notice Set the minimum threshold of `RESOURCE` tokens required to perform a release
  /// @dev only callable by `thresholdSetter`
  function setThreshold(uint256 newThreshold) external;
}
