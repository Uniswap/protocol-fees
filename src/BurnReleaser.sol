// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {AssetSink} from "./AssetSink.sol";

contract Firepit {
  IERC20 public immutable RESOURCE;
  uint256 public immutable THRESHOLD;
  AssetSink public immutable ASSET_SINK;

  constructor(address _resource, uint256 _threshold, address _assetSink) {
    RESOURCE = IERC20(_resource);
    THRESHOLD = _threshold;
    ASSET_SINK = AssetSink(_assetSink);
  }

  function torch(Currency[] memory assets, address recipient) external {
    RESOURCE.transferFrom(msg.sender, address(0), THRESHOLD);

    for (uint256 i = 0; i < assets.length; i++) {
      ASSET_SINK.release(assets[i], recipient);
    }
  }
}
