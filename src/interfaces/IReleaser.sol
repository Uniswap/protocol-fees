// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IAssetSink} from "./IAssetSink.sol";
import {IResourceManager} from "./base/IResourceManager.sol";

interface IReleaser is IResourceManager {
  function ASSET_SINK() external view returns (IAssetSink);
  function release(uint256 _nonce, Currency[] memory assets, address recipient) external;
}
