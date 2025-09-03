// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {ExchangeReleaser} from "./ExchangeReleaser.sol";

/// @title Firepit
/// @notice An ExchangeReleaser with recipient set to the burn address address(0)
contract Firepit is ExchangeReleaser {
  constructor(
    address _owner,
    address _thresholdSetter,
    address _resource,
    uint256 _threshold,
    address _assetSink
  ) ExchangeReleaser(_owner, _thresholdSetter, _resource, _threshold, _assetSink, address(0)) {}
}
