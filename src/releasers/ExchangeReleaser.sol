// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {SafeTransferLib, ERC20} from "solmate/src/utils/SafeTransferLib.sol";
import {FirepitImmutable} from "../base/FirepitImmutable.sol";
import {AssetSink} from "../AssetSink.sol";
import {Nonce} from "../base/Nonce.sol";

/// @title ExchangeReleaser
/// @notice A contract that releases assets from an AssetSink in exchange for transferring a
/// threshold
/// amount of a resource token
/// @dev Inherits from FirepitImmutable for resource transferring functionality and Nonce for replay
/// protection
contract ExchangeReleaser is FirepitImmutable, Nonce {
  using SafeTransferLib for ERC20;

  /// @notice The AssetSink contract from which assets will be released
  AssetSink public immutable ASSET_SINK;

  /// @notice The recipient address that receives the resource tokens
  address public immutable RESOURCE_RECIPIENT;

  /// @notice Creates a new ExchangeReleaser instance
  /// @param _owner The owner of the contract
  /// @param _thresholdSetter The address authorized to set the threshold
  /// @param _resource The address of the resource token that must be transferred
  /// @param _threshold The amount of resource tokens required to trigger a release
  /// @param _assetSink The address of the AssetSink contract holding the assets
  /// @param _recipient The address that will receive the resource tokens
  constructor(
    address _owner,
    address _thresholdSetter,
    address _resource,
    uint256 _threshold,
    address _assetSink,
    address _recipient
  ) FirepitImmutable(_resource, _threshold, _owner, _thresholdSetter) {
    ASSET_SINK = AssetSink(payable(_assetSink));
    RESOURCE_RECIPIENT = _recipient;
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

    for (uint256 i = 0; i < assets.length; i++) {
      ASSET_SINK.release(assets[i], recipient);
    }
  }
}
