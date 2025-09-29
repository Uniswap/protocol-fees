// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IReleaser} from "../interfaces/IReleaser.sol";
import {ExchangeReleaser} from "./ExchangeReleaser.sol";

/// @title Firepit
/// @notice An ExchangeReleaser with recipient set to the burn address address(0xdead) and a limit
/// on the number of currencies that can be released at any time.
/// @custom:security-contact security@uniswap.org
contract Firepit is ExchangeReleaser {
  /// @notice Thrown when attempting to release too many assets at once
  error TooManyAssets();

  /// @notice Maximum number of different assets that can be released in a single call
  uint256 public constant MAX_RELEASE_LENGTH = 20;

  constructor(address _resource, uint256 _threshold, address _assetSink)
    ExchangeReleaser(_resource, _threshold, _assetSink, address(0xdead))
  {}

  /// @inheritdoc IReleaser
  function release(uint256 _nonce, Currency[] calldata assets, address recipient) external override {
    require(assets.length <= MAX_RELEASE_LENGTH, TooManyAssets());
    _release(_nonce, assets, recipient);
  }
}
