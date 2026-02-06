// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {IL2GatewayRouter} from "../interfaces/external/IL2GatewayRouter.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ExchangeReleaser} from "./ExchangeReleaser.sol";

/// @title ArbitrumBridgedResourceFirepit
/// @notice A releaser that implements a two-stage burn process for bridged resource tokens on
/// Arbitrum
/// @dev Two-stage burn from Arbitrum L2 to the underlying resource on L1
/// **Stage 1: L2 Collection and Bridge Initiation**
/// - User calls `release()` providing resource tokens as payment
/// - ExchangeReleaser transfers resource tokens from user to this smart contract
/// - TokenJar releases accumulated fee assets to the specified recipient
/// - _afterRelease() initiates bridge withdrawal to L1 burn address (0xdead)
/// **Stage 2: L1 Finalization**
/// - L2GatewayRouter burns the L2 tokens held by this contract
/// - Cross-domain message is queued (~7-day challenge period on mainnet)
/// - After challenge period, L1 gateway releases escrowed tokens to 0xdead on L1
contract ArbitrumBridgedResourceFirepit is ExchangeReleaser {
  using SafeTransferLib for ERC20;

  /// @dev The L2 Gateway Router address on Arbitrum One
  /// @dev This is not a predeploy - it's a regular deployed contract
  address public constant L2_GATEWAY_ROUTER = 0x5288c571Fd7aD117beA99bF60FE0846C4E84F933;

  /// @dev The L1 UNI token address (Ethereum mainnet)
  /// @dev Required for Arbitrum gateway calls which use L1 token address
  address public immutable L1_RESOURCE;

  /// @dev Final recipient of the bridged resource on L1 (burn address)
  /// @dev Note: This is different from RESOURCE_RECIPIENT which is address(this) on L2
  address internal constant L1_RESOURCE_RECIPIENT = address(0xdead);

  /// @notice Creates a new ArbitrumBridgedResourceFirepit instance
  /// @param _resource The address of the resource token on Arbitrum (L2 bridged token)
  /// @param _l1Resource The address of the resource token on Ethereum (L1 original token)
  /// @param _threshold The minimum amount of resource tokens required for exchange
  /// @param _tokenJar The address of the TokenJar contract holding accumulated fee assets
  /// @dev Sets RESOURCE_RECIPIENT to address(this) to enable the two-stage burn:
  ///      Stage 1: Collect tokens here (L2) -> Stage 2: Bridge and burn on L1
  constructor(address _resource, address _l1Resource, uint256 _threshold, address _tokenJar)
    ExchangeReleaser(_resource, _threshold, _tokenJar, address(this))
  {
    require(_l1Resource != address(0), "ArbitrumBridgedResourceFirepit: l1Resource is zero");
    L1_RESOURCE = _l1Resource;
  }

  /// @notice Hook called after assets are released - initiates stage 2 withdrawal to L1
  function _afterRelease(Currency[] calldata, address) internal override {
    // Stage 2: Initiate bridge withdrawal to L1 burn address
    // The gateway will:
    // 1. Burn the L2 tokens held by this contract
    // 2. Queue a cross-domain message for L1
    // 3. After challenge period, release underlying resource tokens to 0xdead on L1
    IL2GatewayRouter(L2_GATEWAY_ROUTER)
      .outboundTransfer(
        L1_RESOURCE, // L1 token address (required by Arbitrum gateway)
        L1_RESOURCE_RECIPIENT, // Destination on L1 (burn address)
        threshold, // Amount to withdraw
        bytes("") // Empty extra data for standard withdrawal
      );
  }
}
