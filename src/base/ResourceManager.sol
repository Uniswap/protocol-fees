// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Owned} from "solmate/src/auth/Owned.sol";
import {ERC20} from "solmate/src/utils/SafeTransferLib.sol";
import {IResourceManager} from "../interfaces/IReleaser.sol";

/// @title ResourceManager
/// @notice A contract that holds immutable state for the resource token and the resource recipient
/// address. It also maintains logic for managing the threshold of the resource token.
abstract contract ResourceManager is IResourceManager, Owned {
  /// @inheritdoc IResourceManager
  uint256 public threshold;

  /// @inheritdoc IResourceManager
  address public thresholdSetter;

  /// @inheritdoc IResourceManager
  ERC20 public immutable RESOURCE;

  /// @inheritdoc IResourceManager
  address public immutable RESOURCE_RECIPIENT;

  /// @notice Ensures only the threshold setter can call the setThreshold function
  modifier onlyThresholdSetter() {
    if (msg.sender != thresholdSetter) revert Unauthorized();
    _;
  }

  /// @dev At construction the thresholdSetter defaults to 0 and its on the owner to set.
  constructor(address _resource, uint256 _threshold, address _owner, address _recipient)
    Owned(_owner)
  {
    RESOURCE = ERC20(_resource);
    RESOURCE_RECIPIENT = _recipient;
    threshold = _threshold;
  }

  /// @inheritdoc IResourceManager
  function setThresholdSetter(address _thresholdSetter) external onlyOwner {
    thresholdSetter = _thresholdSetter;
  }

  /// @inheritdoc IResourceManager
  function setThreshold(uint256 _threshold) external onlyThresholdSetter {
    threshold = _threshold;
  }
}
