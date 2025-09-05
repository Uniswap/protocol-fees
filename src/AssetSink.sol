// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {IAssetSink} from "./interfaces/IAssetSink.sol";

/// @title AssetSink
/// @notice Sink for protocol fees
/// @dev Fees accumulate passively in this contract from external sources.
///      Stored fees can be released by authorized releaser contracts.
contract AssetSink is Owned, IAssetSink {
  /// @inheritdoc IAssetSink
  address public releaser;

  /// @notice Ensures only the releaser can call the release function
  modifier onlyReleaser() {
    if (msg.sender != releaser) revert Unauthorized();
    _;
  }

  /// @notice Creates a new AssetSink with the specified releaser
  constructor() Owned(msg.sender) {}

  /// @inheritdoc IAssetSink
  function release(Currency[] calldata assets, address recipient) external onlyReleaser {
    Currency asset;
    uint256 amount;
    for (uint256 i; i < assets.length; i++) {
      asset = assets[i];
      amount = asset.balanceOfSelf();
      if (amount > 0) {
        asset.transfer(recipient, amount);
        emit FeesClaimed(asset, recipient, amount);
      }
    }
  }

  /// @inheritdoc IAssetSink
  function setReleaser(address _releaser) external onlyOwner {
    releaser = _releaser;
  }

  receive() external payable {}
}
