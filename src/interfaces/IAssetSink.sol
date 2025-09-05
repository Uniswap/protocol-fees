// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";

/// @title Asset Sink Interface
/// @notice The interface for releasing assets from the contract
interface IAssetSink {
  /// @notice Emitted when asset fees are successfully claimed
  /// @param asset Address of the asset that was claimed
  /// @param recipient Address that received the assets
  /// @param amount Amount of fees transferred to the recipient
  event FeesClaimed(Currency indexed asset, address indexed recipient, uint256 amount);

  /// @notice Thrown when an unauthorized address attempts to call a restricted function
  error Unauthorized();

  /// @return Address of the current IReleaser
  /// @dev The releaser has exclusive access to the `release()` function
  function releaser() external view returns (address);

  /// @notice Set the address of the IReleaser contract
  /// @dev only callabe by `owner`
  function setReleaser(address _releaser) external;

  /// @notice Release assets to a specified recipient
  /// @dev only callable by `releaser`
  function release(Currency[] calldata assets, address recipient) external;
}
