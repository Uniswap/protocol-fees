// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IAssetSink} from "./IAssetSink.sol";
import {IResourceManager} from "./base/IResourceManager.sol";
import {INonce} from "./base/INonce.sol";

interface IReleaser is IResourceManager, INonce {
  /// @return Address of the Asset Sink contract that will release the assets
  function ASSET_SINK() external view returns (IAssetSink);

  /// @notice Releases assets to a specified recipient if the resource threshold is met
  /// @param _nonce The nonce for the release, must equal to the contract nonce otherwise revert
  /// @param assets The list of assets to release, which may have length limits
  /// @param recipient The address to receive the released assets, paid out by Asset Sink
  function release(uint256 _nonce, Currency[] memory assets, address recipient) external;
}
