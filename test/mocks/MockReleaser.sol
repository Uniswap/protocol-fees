// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {TokenJar} from "../../src/TokenJar.sol";

/// @title MockReleaser
/// @notice Mock contract for testing TokenJar functionality
contract MockReleaser {
  TokenJar public assetSink;

  constructor(address _assetSink) {
    assetSink = TokenJar(payable(_assetSink));
  }

  function setTokenJar(TokenJar _assetSink) external {
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
