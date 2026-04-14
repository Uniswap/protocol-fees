// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {ExchangeReleaser} from "./ExchangeReleaser.sol";

import {NttManagerNoRateLimiting} from "lib/native-token-transfers/evm/src/NttManager/NttManagerNoRateLimiting.sol";

/// @title WormholeReleaser
/// @notice A releaser that triggers a Wormhole Native Token Transfer message sent back to Ethereum.
/// @dev Process is as follows:
/// 1. User calls `release` on this contract.
/// 2. This contract transfers `SyntheticNttUni` from the user to here.
/// 3. This contract calls `release` on the `TokenJar`.
/// 4. This contract initiates a Womrhole Native Token Transfer by calling `transfer` on `NTT_MANAGER`.
///    a. The `NTT_MANAGER` calls `burn` on `SyntheticNttUni` locally.
///    b. The `NTT_MANAGER` passes a message on to Ethereum to burn UNI via `transfer(0xdead, threshold)`.
///    c. The NTT Manager on Ethereum facilitates the final burn to `0xdead`.
contract WormholeReleaser is ExchangeReleaser {
  /// @dev Wormhole defines a custom chain id for each chain, they set Ethereum chain ID to 2.
  uint16 public constant WORMHOLE_DEFINED_ETH_CHAIN_ID = 2;

  /// @dev Final burn address for the `transfer` message forwarded by the `NTT_MANAGER`.
  bytes32 internal constant BURN_ADDRESS = bytes32(uint256(uint160(address(0xdead))));

  /// @dev Wormhole Native Token Transfer manager, manages the mint/burn mechanism for crosschain
  /// UNI interactions, forwards the message to Ethereum for the final burn.
  NttManagerNoRateLimiting public immutable NTT_MANAGER;

  /// @notice Creates the Wormhole Releaser.
  /// @param _nttManager NTT Manager contract.
  /// @param _resource Local UNI deployment (`SyntheticNttUni`).
  /// @param _threshold The minimum amount of resource tokens required for exchange.
  /// @param _tokenJar The address of the TokenJar contract holding accumulated fees.
  constructor(address _nttManager, address _resource, uint256 _threshold, address _tokenJar)
    ExchangeReleaser(_resource, _threshold, _tokenJar, address(this))
  {
    NTT_MANAGER = NttManagerNoRateLimiting(_nttManager);
  }

  /// @notice Hook called after assets are released - initiates transfer message for final burn.
  function _afterRelease(Currency[] calldata, address) internal override {
    NTT_MANAGER.transfer({
        amount: threshold,
        recipientChain: WORMHOLE_DEFINED_ETH_CHAIN_ID,
        recipient: BURN_ADDRESS
    });
  }
}
