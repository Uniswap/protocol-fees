// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {AssetSink} from "../../src/AssetSink.sol";

/// @title MockReleaser
/// @notice Mock contract for testing AssetSink functionality
contract MockReleaser {
  AssetSink public assetSink;

  constructor(address _assetSink) {
    assetSink = AssetSink(payable(_assetSink));
  }

  function setAssetSink(AssetSink _assetSink) external {
    assetSink = _assetSink;
  }

  /// @notice Release assets from the sink
  function release(Currency asset, address recipient) external {
    Currency[] memory assets = new Currency[](1);
    assets[0] = asset;
    assetSink.release(assets, recipient);
  }

  /// @notice Release assets to caller
  function releaseToCaller(Currency asset) external {
    Currency[] memory assets = new Currency[](1);
    assets[0] = asset;
    assetSink.release(assets, msg.sender);
  }
}

/// @title MockRevertingReceiver
/// @notice Mock contract that reverts on receiving native tokens
contract MockRevertingReceiver {
  receive() external payable {
    revert("MockRevertingReceiver: revert on receive");
  }

  fallback() external payable {
    revert("MockRevertingReceiver: revert on fallback");
  }
}
