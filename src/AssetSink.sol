// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

/// @title AssetSink
/// @notice Sink for protocol fees
/// @dev Fees accumulate passively in this contract from external sources.
///      Stored fees can be released by authorized releaser contracts.
contract AssetSink {
  using CurrencyLibrary for Currency;

  /// @notice Emitted when asset fees are successfully claimed
  /// @param asset Address of the currency that was claimed
  /// @param recipient Address that received the assets
  /// @param amount Amount of fees transferred to the recipient
  event FeesClaimed(Currency indexed asset, address indexed recipient, uint256 amount);

  /// @notice Thrown when an unauthorized address attempts to call a restricted function
  error Unauthorized();

  /// @notice Address that can release assets from the sink
  address public immutable releaser;

  /// @notice Ensures only the releaser can call the modified function
  modifier onlyReleaser() {
    if (msg.sender != releaser) revert Unauthorized();
    _;
  }

  /// @notice Creates a new AssetSink with the specified releaser
  /// @param _releaser The address that is allowed to release assets from the sink
  constructor(address _releaser) {
    releaser = _releaser;
  }

  /// @notice Releases all accumulated assets to the specified recipient
  /// @param asset The asset to release
  /// @param recipient The address to receive the assets
  /// @dev Only callable by the releaser address
  function release(Currency asset, address recipient) external onlyReleaser {
    uint256 amount = asset.balanceOfSelf();
    if (amount > 0) {
      asset.transfer(recipient, amount);
      emit FeesClaimed(asset, recipient, amount);
    }
  }
}
