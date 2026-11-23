// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IXLayerBridge} from "../../src/interfaces/external/IXLayerBridge.sol";

/// @dev Mock of the X Layer unified bridge. Mirrors the three `bridgeAsset`
/// ERC20 paths: a bridge-minted wrapped token is burned from the caller directly, a "not mintable"
/// sovereign token is pulled through the caller's allowance and escrowed, and a token with no
/// mapping is treated as native to this network, pulled through the allowance and escrowed.
contract MockXLayerBridge is IXLayerBridge {
  error DestinationNetworkInvalid();
  error MsgValueNotZero();
  error OnlyNotEmergencyState();

  struct TokenInformation {
    uint32 originNetwork;
    address originTokenAddress;
  }

  uint32 public immutable override networkID;
  uint32 public depositCount;
  bool public emergencyState;

  mapping(address => TokenInformation) internal tokenInfo;
  mapping(address => bool) public wrappedAddressIsNotMintable;
  mapping(uint32 => mapping(address => address)) internal wrapped;

  constructor(uint32 _networkID) {
    networkID = _networkID;
  }

  function setWrappedToken(address token, uint32 originNetwork, address originTokenAddress)
    external
  {
    tokenInfo[token] = TokenInformation(originNetwork, originTokenAddress);
    wrapped[originNetwork][originTokenAddress] = token;
  }

  /// @dev Mirrors `AgglayerBridgeL2.removeLegacySovereignTokenAddress`, which deletes a legacy
  /// token's mapping once its origin token has been remapped to a new sovereign token
  function removeWrappedToken(address token) external {
    delete tokenInfo[token];
    delete wrappedAddressIsNotMintable[token];
  }

  function setNotMintable(address token, bool notMintable) external {
    wrappedAddressIsNotMintable[token] = notMintable;
  }

  function setEmergencyState(bool active) external {
    emergencyState = active;
  }

  function bridgeAsset(
    uint32 destinationNetwork,
    address destinationAddress,
    uint256 amount,
    address token,
    bool,
    bytes calldata
  ) external payable override {
    require(!emergencyState, OnlyNotEmergencyState());
    require(destinationNetwork != networkID, DestinationNetworkInvalid());
    require(msg.value == 0, MsgValueNotZero());

    TokenInformation memory info = tokenInfo[token];

    if (info.originTokenAddress == address(0)) {
      MockERC20(token).transferFrom(msg.sender, address(this), amount);
      info = TokenInformation(networkID, token);
    } else if (wrappedAddressIsNotMintable[token]) {
      MockERC20(token).transferFrom(msg.sender, address(this), amount);
    } else {
      MockERC20(token).burn(msg.sender, amount);
    }

    emit BridgeEvent(
      0,
      info.originNetwork,
      info.originTokenAddress,
      destinationNetwork,
      destinationAddress,
      amount,
      "",
      depositCount++
    );
  }

  function wrappedTokenToTokenInfo(address wrappedToken)
    external
    view
    override
    returns (uint32, address)
  {
    TokenInformation memory info = tokenInfo[wrappedToken];
    return (info.originNetwork, info.originTokenAddress);
  }

  function getTokenWrappedAddress(uint32 originNetwork, address originTokenAddress)
    external
    view
    override
    returns (address)
  {
    return wrapped[originNetwork][originTokenAddress];
  }
}
