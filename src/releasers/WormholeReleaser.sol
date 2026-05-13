// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";

import {ExchangeReleaser} from "./ExchangeReleaser.sol";

import {INttManager} from "../interfaces/wormhole/INttManager.sol";

/// @title WormholeReleaser
/// @notice A releaser that triggers a Wormhole Native Token Transfer message sent back to Ethereum.
/// @dev Process is as follows:
/// 1. User calls `release` on this contract.
/// 2. This contract transfers `SyntheticNttUni` from the user to here.
/// 3. This contract calls `release` on the `TokenJar`.
/// 4. This contract initiates a Womrhole Native Token Transfer by calling `transfer` on
/// `NTT_MANAGER`. a. The `NTT_MANAGER` calls `burn` on `SyntheticNttUni` locally.
///    b. The `NTT_MANAGER` passes a message on to Ethereum to burn UNI via `transfer(0xdead,
/// threshold)`. c. The NTT Manager on Ethereum facilitates the final burn to `0xdead`.
/// @custom:security-contact security@uniswap.org
contract WormholeReleaser is ExchangeReleaser {
  /// @dev Thrown when the `release` function fails to refund Ether to the caller after sending a
  /// message to Wormhole. Note that any nonzero Ether balance in this releaser after an NttManager
  /// call implies a refund will be attempted.
  error SenderRefundFailed();

  /// @dev Wormhole defines a custom chain id for each chain, they set Ethereum chain ID to 2.
  uint16 public constant WORMHOLE_DEFINED_ETH_CHAIN_ID = 2;

  /// @dev Final burn address for the `transfer` message forwarded by the `NTT_MANAGER`.
  bytes32 public immutable BURN_ADDRESS = bytes32(uint256(uint160(address(0xdead))));

  /// @dev Wormhole Native Token Transfer manager, manages the mint/burn mechanism for crosschain
  /// UNI interactions, forwards the message to Ethereum for the final burn.
  INttManager public immutable NTT_MANAGER;

  /// @notice Creates the Wormhole Releaser.
  /// @param _nttManager NTT Manager contract.
  /// @param _resource Local UNI deployment (`SyntheticNttUni`).
  /// @param _threshold The minimum amount of resource tokens required for exchange.
  /// @param _tokenJar The address of the TokenJar contract holding accumulated fees.
  constructor(address _nttManager, address _resource, uint256 _threshold, address _tokenJar)
    ExchangeReleaser(_resource, _threshold, _tokenJar, address(this))
  {
    NTT_MANAGER = INttManager(_nttManager);
  }

  /// @notice Hook called after assets are released - initiates transfer message for final burn.
  /// @dev Wormhole may charge protocol fees, in Ether, in the future. The cost of sending a message
  /// over the NttManager system depends on the total quoted price from all WormholeTransceiver
  /// instances used by the NttManager. This contract MUST have sufficient Ether to send the total
  /// quoted price from `NttManager.quoteDeliveryPrice`.
  /// @dev Wormhole clips the decimals down to 8 to accommodate Solana chains. Since forcing the
  /// trim at `setThreshold` time would require changes up the contract inheritance tree, divergeing
  /// inheritance tree across deployments, instead we clip at `release` time.
  /// @dev WARNING: If governance sets a non-multiple of 1e10, dust will accumulate here.
  function _afterRelease(Currency[] calldata, address) internal override {
    (, uint256 totalQuote) = NTT_MANAGER.quoteDeliveryPrice({
      recipientChain: WORMHOLE_DEFINED_ETH_CHAIN_ID, transceiverInstructions: new bytes(1)
    });

    uint256 amount = wormholeTrim(threshold);

    RESOURCE.approve(address(NTT_MANAGER), amount);

    NTT_MANAGER.transfer{value: totalQuote}({
      amount: amount, recipientChain: WORMHOLE_DEFINED_ETH_CHAIN_ID, recipient: BURN_ADDRESS
    });

    if (address(this).balance > 0) {
      (bool success,) = msg.sender.call{value: address(this).balance}(new bytes(0));
      require(success, SenderRefundFailed());
    }
  }

  /// @notice Helper function for trimming decimals. Publicly exposed for clarity's sake.
  /// @dev All UNI tokens use 18 decimals, all Wormhole Ntt transfers use 8 deciamls. So we clip 10.
  function wormholeTrim(uint256 amount) public pure returns (uint256) {
    return amount / 1e10 * 1e10;
  }

  /// @dev Receives Ether ahead of a `release` call. WARNING: if `release` is not called atomically
  /// with Ether being sent to this function means the caller can lose their Ether.
  receive() external payable {}
}
