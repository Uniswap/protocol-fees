// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {ExchangeReleaser} from "../../src/releasers/ExchangeReleaser.sol";

contract ExchangeReleaserMock is ExchangeReleaser {
  constructor(address _resource, uint256 _threshold, address _assetSink, address _recipient)
    ExchangeReleaser(_resource, _threshold, _assetSink, _recipient)
  {}

  function release(uint256 _nonce, Currency[] memory assets, address recipient) external override {
    _release(_nonce, assets, recipient);
  }
}
