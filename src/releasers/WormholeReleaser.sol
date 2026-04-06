// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ExchangeReleaser} from "./ExchangeReleaser.sol";
import {IWormhole} from "../interfaces/wormhole/IWormhole.sol";
import {IWormholeRelayer} from "../interfaces/wormhole/IWormholeRelayer.sol";
import {IWormholeWrappedTokenTransfer} from "../interfaces/wormhole/IWormholeWrappedTokenTransfer.sol";
import {ResourceManager} from "../base/ResourceManager.sol";
import {Nonce} from "../base/Nonce.sol";
import {ITokenJar} from "../interfaces/ITokenJar.sol";
import {IReleaser} from "../interfaces/IReleaser.sol";

// NOTICE: this is likely not the final code. it is not complete.

// notes:
//
// eth wormhole chain id: 2
//
// wormhole wrapped token transfer bridge
// https://etherscan.io/address/0x3ee18B2214AFF97000D974cf647E7C347E8fa585#code
//
// wormhole
// https://etherscan.io/address/0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B
//
// bnb wormhole chain id: 6
//
// wormohle wrapped token transfer bridge
// https://bscscan.com/address/0xB6F6D86a8f9879A9c87f643768d9efc38c1Da6E7#code
//
// wormhole
// https://bscscan.com/address/0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B#code

/// @title WormholeBridgedResourceFirepit
contract WormholeBridgedResourceFirepit is IReleaser, ResourceManager, Nonce {
  using SafeTransferLib for ERC20;

  error ZeroAddress();

  /// @notice Maximum number of different assets that can be released in a single call
  uint256 public constant MAX_RELEASE_LENGTH = 20;

  uint16 public constant ETH_CHAIN_ID_FROM_WORMHOLE = 2;

  uint16 public constant BNB_CHAIN_ID_FROM_WORMHOLE = 6;

  /// @inheritdoc IReleaser
  ITokenJar public immutable TOKEN_JAR;

  /// @dev The L1 UNI token address (Ethereum mainnet)
  address public immutable L1_RESOURCE;

  address public immutable WORMHOLE;
  address public immutable WORMHOLE_RELAYER;
  address public immutable WORMHOLE_WRAPPED_TOKEN_TRANSFER;
  uint32 public wormholeNonce;

  address internal constant L1_RESOURCE_RECIPIENT = address(0xdead);

  /// @notice Creates a new ExchangeReleaser instance
  /// @param _resource The address of the resource token that must be transferred
  /// @param _threshold The minimum amount of resource tokens that must be transferred
  /// @param _tokenJar The address of the TokenJar contract holding the assets
  /// @param _recipient The address that will receive the resource tokens
  constructor(
    address _resource,
    address _l1Resource,
    uint256 _threshold,
    address _tokenJar,
    address _recipient,
    address _wormhole,
    address _wormholeRelayer,
    address _wormholeWrappedTokenTransfer
  )
    ResourceManager(_resource, _threshold, msg.sender, _recipient)
  {
    TOKEN_JAR = ITokenJar(payable(_tokenJar));
    L1_RESOURCE = _l1Resource;
    WORMHOLE = _wormhole;
    WORMHOLE_RELAYER = _wormholeRelayer;
    WORMHOLE_WRAPPED_TOKEN_TRANSFER = _wormholeWrappedTokenTransfer;
  }

  /// @inheritdoc IReleaser
  function release(uint256 _nonce, Currency[] calldata assets, address recipient)
    external
    handleNonce(_nonce)
  {
    require(assets.length <= MAX_RELEASE_LENGTH, TooManyAssets());
    RESOURCE.safeTransferFrom(msg.sender, RESOURCE_RECIPIENT, threshold);
    TOKEN_JAR.release(assets, recipient);
    emit Released(_nonce, recipient, assets);

    _afterRelease(assets, recipient);
  }

  /// @notice Hook called after assets are released. Invokes the Wormhole wrapped transfer token
  /// bridge.
  function _afterRelease(Currency[] calldata, address) internal {
    uint256 wormholeFee = IWormhole(WORMHOLE).messageFee();
    IWormholeWrappedTokenTransfer(WORMHOLE_WRAPPED_TOKEN_TRANSFER)
      .transferTokens{value: wormholeFee}(
        L1_RESOURCE,
        threshold,
        ETH_CHAIN_ID_FROM_WORMHOLE,
        bytes32(uint256(uint160(L1_RESOURCE_RECIPIENT))),
        0,
        uint32(nonce)
      );
  }
}
