// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {SafeTransferLib, ERC20} from "solmate/src/utils/SafeTransferLib.sol";
import {FirepitImmutable} from "../base/FirepitImmutable.sol";
import {AssetSink} from "../AssetSink.sol";
import {Nonce} from "../base/Nonce.sol";
import {SwapReleaser} from "./SwapReleaser.sol";

contract Firepit is SwapReleaser {
  constructor(address _resource, uint256 _threshold, address _assetSink)
    SwapReleaser(_resource, _threshold, _assetSink, address(0))
  {}
}
