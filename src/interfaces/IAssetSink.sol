// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";

interface IAssetSink {
  /// @notice Emitted when asset fees are successfully claimed
  /// @param asset Address of the asset that was claimed
  /// @param recipient Address that received the assets
  /// @param amount Amount of fees transferred to the recipient
  event FeesClaimed(Currency indexed asset, address indexed recipient, uint256 amount);

  /// @notice Thrown when an unauthorized address attempts to call a restricted function
  error Unauthorized();

  function releaser() external view returns (address);
  function setReleaser(address _releaser) external;
  function release(Currency[] calldata assets, address recipient) external;
}
