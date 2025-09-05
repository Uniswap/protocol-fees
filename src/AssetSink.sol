// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {Owned} from "solmate/src/auth/Owned.sol";

/// @title AssetSink
/// @notice Sink for protocol fees
/// @dev Fees accumulate passively in this contract from external sources.
///      Stored fees can be released by authorized releaser contracts.
contract AssetSink is Owned {
  /// @notice Emitted when asset fees are successfully claimed
  /// @param asset Address of the asset that was claimed
  /// @param recipient Address that received the assets
  /// @param amount Amount of fees transferred to the recipient
  event FeesClaimed(Currency indexed asset, address indexed recipient, uint256 amount);

  /// @notice Thrown when an unauthorized address attempts to call a restricted function
  error Unauthorized();

  /// @notice Thrown when attempting to release too many assets at once
  error TooManyAssets();

  /// @notice Address that can release assets from the sink
  address public releaser;

  /// @notice Maximum number of different assets that can be released in a single call
  uint256 public constant MAX_RELEASE_LENGTH = 20;

  /// @notice Ensures only the releaser can call the modified function
  modifier onlyReleaser() {
    if (msg.sender != releaser) revert Unauthorized();
    _;
  }

  /// @notice Creates a new AssetSink with the specified releaser

  constructor() Owned(msg.sender) {}

  /// @notice Releases all accumulated assets to the specified recipient
  /// @param assets an array of Currencies to release
  /// @param recipient The address to receive the assets
  /// @dev Only callable by the releaser address. WILL REVERT on transfer failure(s)
  function release(Currency[] calldata assets, address recipient) external onlyReleaser {
    require(assets.length <= MAX_RELEASE_LENGTH, TooManyAssets());
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

  function setReleaser(address _releaser) external onlyOwner {
    releaser = _releaser;
  }

  receive() external payable {}
}
