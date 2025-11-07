// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {TokenJar} from "../../src/TokenJar.sol";

/// @title MockReleaser
/// @notice Mock contract for testing TokenJar functionality
contract MockReleaser {
  TokenJar public tokenJar;

  constructor(address _tokenJar) {
    tokenJar = TokenJar(payable(_tokenJar));
  }

  function setTokenJar(TokenJar _tokenJar) external {
    tokenJar = _tokenJar;
  }

  /// @notice Release assets from the token jar
  function release(Currency asset, address recipient) external {
    Currency[] memory assets = new Currency[](1);
    assets[0] = asset;
    tokenJar.release(assets, recipient);
  }

  /// @notice Release assets to caller
  function releaseToCaller(Currency asset) external {
    Currency[] memory assets = new Currency[](1);
    assets[0] = asset;
    tokenJar.release(assets, msg.sender);
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
