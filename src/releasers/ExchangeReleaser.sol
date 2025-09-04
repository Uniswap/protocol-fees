// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {SafeTransferLib, ERC20} from "solmate/src/utils/SafeTransferLib.sol";
import {ResourceManager} from "../base/ResourceManager.sol";
import {AssetSink} from "../AssetSink.sol";
import {Nonce} from "../base/Nonce.sol";

/// @title ExchangeReleaser
/// @notice A contract that releases assets from an AssetSink in exchange for transferring a
/// threshold
/// amount of a resource token
/// @dev Inherits from ResourceManager for resource transferring functionality and Nonce for replay
/// protection
contract ExchangeReleaser is ResourceManager, Nonce {
  using SafeTransferLib for ERC20;

  /// @notice The AssetSink contract from which assets will be released
  AssetSink public immutable ASSET_SINK;

  /// @notice Creates a new ExchangeReleaser instance
  /// @param _resource The address of the resource token that must be transferred
  /// @param _assetSink The address of the AssetSink contract holding the assets
  /// @param _recipient The address that will receive the resource tokens
  constructor(address _resource, address _assetSink, address _recipient)
    ResourceManager(_resource, msg.sender, _recipient)
  {
    ASSET_SINK = AssetSink(payable(_assetSink));
  }

  /// @notice Releases specified assets to the recipient in return for threshold resource tokens
  /// @dev Transfers the threshold amount of resource tokens from msg.sender to RECIPIENT, then
  /// releases all specified assets
  /// @param _nonce A unique nonce to prevent replay attacks
  /// @param assets An array of Currency tokens to be released from the AssetSink
  /// @param recipient The address that will receive the released assets
  function release(uint256 _nonce, Currency[] memory assets, address recipient)
    external
    handleNonce(_nonce)
  {
    RESOURCE.safeTransferFrom(msg.sender, RESOURCE_RECIPIENT, threshold);
    ASSET_SINK.release(assets, recipient);
  }
}
