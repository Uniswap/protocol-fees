// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {SafeTransferLib, ERC20} from "solmate/src/utils/SafeTransferLib.sol";
import {FirepitImmutable} from "./base/FirepitImmutable.sol";
import {AssetSink} from "./AssetSink.sol";
import {Nonce} from "./base/Nonce.sol";

contract Firepit is FirepitImmutable, Nonce {
  using SafeTransferLib for ERC20;

  AssetSink public immutable ASSET_SINK;

  constructor(
    address _owner,
    address _thresholdSetter,
    address _resource,
    uint256 _threshold,
    address _assetSink
  ) FirepitImmutable(_resource, _threshold, _owner, _thresholdSetter) {
    ASSET_SINK = AssetSink(payable(_assetSink));
  }

  function torch(uint256 _nonce, Currency[] memory assets, address recipient)
    external
    handleNonce(_nonce)
  {
    RESOURCE.safeTransferFrom(msg.sender, address(0), threshold);

    for (uint256 i = 0; i < assets.length; i++) {
      ASSET_SINK.release(assets[i], recipient);
    }
  }
}
