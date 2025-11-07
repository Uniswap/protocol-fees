// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ResourceManager} from "../base/ResourceManager.sol";
import {Nonce} from "../base/Nonce.sol";
import {ITokenJar} from "../interfaces/ITokenJar.sol";
import {IReleaser} from "../interfaces/IReleaser.sol";

/// @title ExchangeReleaser
/// @notice A contract that releases assets from an TokenJar in exchange for transferring a
/// threshold
/// amount of a resource token
/// @dev Inherits from ResourceManager for resource transferring functionality and Nonce for replay
/// protection
/// @custom:security-contact security@uniswap.org
abstract contract ExchangeReleaser is IReleaser, ResourceManager, Nonce {
  using SafeTransferLib for ERC20;

  /// @inheritdoc IReleaser
  ITokenJar public immutable ASSET_SINK;

  /// @notice Creates a new ExchangeReleaser instance
  /// @param _resource The address of the resource token that must be transferred
  /// @param _assetSink The address of the TokenJar contract holding the assets
  /// @param _recipient The address that will receive the resource tokens
  constructor(address _resource, uint256 _threshold, address _assetSink, address _recipient)
    ResourceManager(_resource, _threshold, msg.sender, _recipient)
  {
    ASSET_SINK = ITokenJar(payable(_assetSink));
  }

  /// @inheritdoc IReleaser
  function release(uint256 _nonce, Currency[] calldata assets, address recipient) external virtual {
    _release(_nonce, assets, recipient);
  }

  /// @notice Internal function to handle the nonce check, transfer the RESOURCE, and call the
  /// release of assets on the TokenJar.
  function _release(uint256 _nonce, Currency[] calldata assets, address recipient)
    internal
    handleNonce(_nonce)
  {
    RESOURCE.safeTransferFrom(msg.sender, RESOURCE_RECIPIENT, threshold);
    ASSET_SINK.release(assets, recipient);
  }
}
