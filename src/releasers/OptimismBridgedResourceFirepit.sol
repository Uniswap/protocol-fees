// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Predeploys} from "@eth-optimism-bedrock/src/libraries/Predeploys.sol";
import {IL2StandardBridge} from "../interfaces/external/IL2StandardBridge.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ExchangeReleaser} from "./ExchangeReleaser.sol";

/// @title OptimismBridgedResourceFirepit
/// @notice A releaser that implements a two-stage burn process for bridged resource tokens
/// @dev Two-stage burn from an OP Stack L2 to the underlying resource on L1
/// **Stage 1: L2 Collection and Bridge Initiation**
/// - User calls `release()` providing resource tokens as payment
/// - ExchangeReleaser transfers resource tokens from user to this smart contract
/// - TokenJar releases accumulated fee assets to the specified recipient
/// - _afterRelease() initiates bridge withdrawal to L1 burn address (0xdead)
/// **Stage 2: L1 Finalization**
/// - L2StandardBridge burns the L2 tokens held by this contract
/// - Cross-domain message is queued (7-day challenge period on mainnet)
/// - L1StandardBridge finalizes withdrawal and transfers tokens to 0xdead on L1
abstract contract OptimismBridgedResourceFirepit is ExchangeReleaser {
  /// @dev The minimum gas limit for the withdrawal transaction to L1.
  /// @dev Gas required for a simple UNI transfer to 0xdead on L1
  uint32 internal constant WITHDRAWAL_MIN_GAS = 100_000;

  /// @dev Final recipient of the bridged resource on L1 (burn address)
  /// @dev Note: This is different from RESOURCE_RECIPIENT which is address(this) on L2
  address internal constant L1_RESOURCE_RECIPIENT = address(0xdead);

  /// @notice Creates a new OptimismBridgedResourceFirepit instance
  /// @param _resource The address of the resource token (must be OptimismMintableERC20)
  /// @param _threshold The minimum amount of resource tokens required for exchange
  /// @param _tokenJar The address of the TokenJar contract holding accumulated fee assets
  /// @dev Sets RESOURCE_RECIPIENT to address(this) to enable the two-stage burn:
  ///      Stage 1: Collect tokens here (L2) -> Stage 2: Bridge and burn on L1
  constructor(address _resource, uint256 _threshold, address _tokenJar)
    ExchangeReleaser(_resource, _threshold, _tokenJar, address(this))
  {}

  /// @notice Hook called after assets are released - initiates stage 2 withdrawal to L1
  function _afterRelease(Currency[] calldata, address) internal override {
    // Stage 2: Initiate bridge withdrawal to L1 burn address
    // The bridge will:
    // 1. Burn the L2 tokens held by this contract
    // 2. Queue a cross-domain message for L1
    // 3. After challenge period, transfer underlying resource tokens to 0xdead on L1
    IL2StandardBridge(Predeploys.L2_STANDARD_BRIDGE)
      .withdrawTo(
        address(RESOURCE), L1_RESOURCE_RECIPIENT, threshold, WITHDRAWAL_MIN_GAS, bytes("")
      );
  }
}
