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
/// threshold amount of a resource token
/// @dev Inherits from ResourceManager for resource transferring functionality and Nonce for replay
/// protection
/// @custom:security-contact security@uniswap.org
abstract contract ExchangeReleaser is IReleaser, ResourceManager, Nonce {
  using SafeTransferLib for ERC20;

  /// @notice Maximum number of different assets that can be released in a single call
  uint256 public constant MAX_RELEASE_LENGTH = 20;

  /// @inheritdoc IReleaser
  ITokenJar public immutable TOKEN_JAR;

  /// @notice Creates a new ExchangeReleaser instance
  /// @param _resource The address of the resource token that must be transferred
  /// @param _threshold The minimum amount of resource tokens that must be transferred
  /// @param _tokenJar The address of the TokenJar contract holding the assets
  /// @param _recipient The address that will receive the resource tokens
  constructor(address _resource, uint256 _threshold, address _tokenJar, address _recipient)
    ResourceManager(_resource, _threshold, msg.sender, _recipient)
  {
    TOKEN_JAR = ITokenJar(payable(_tokenJar));
  }

  /// @inheritdoc IReleaser
  function release(uint256 _nonce, Currency[] calldata assets, address recipient)
    external
    handleNonce(_nonce)
  {
    require(assets.length <= MAX_RELEASE_LENGTH, TooManyAssets());
    RESOURCE.safeTransferFrom(msg.sender, RESOURCE_RECIPIENT, threshold);
    TOKEN_JAR.release(assets, recipient);
    _afterRelease(assets, recipient);
  }

  /// @notice Internal function to handle any post transfer actions
  /// e.g. bridge calls or notifications
  function _afterRelease(Currency[] calldata assets, address recipient) internal virtual {
    // by default do nothing after release
  }
}
