// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";
import {AssetSink} from "./AssetSink.sol";
import {Nonce} from "./base/Nonce.sol";

contract Firepit is Nonce {
  using SafeTransferLib for ERC20;

  ERC20 public immutable RESOURCE;
  uint256 public immutable THRESHOLD;
  AssetSink public immutable ASSET_SINK;

  constructor(address _resource, uint256 _threshold, address _assetSink) {
    RESOURCE = ERC20(_resource);
    THRESHOLD = _threshold;
    ASSET_SINK = AssetSink(_assetSink);
  }

  function torch(uint256 _nonce, Currency[] memory assets, address recipient)
    external
    handleNonce(_nonce)
  {
    RESOURCE.safeTransferFrom(msg.sender, address(0), THRESHOLD);

    for (uint256 i = 0; i < assets.length; i++) {
      ASSET_SINK.release(assets[i], recipient);
    }
  }
}
