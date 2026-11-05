// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IAggLayerBridge
/// @notice Interface for Polygon's AggLayer unified bridge (`PolygonZkEVMBridgeV2`, since renamed
/// `AgglayerBridge`), deployed on Ethereum and on every AggLayer-connected chain
/// @dev Used to initiate asset withdrawals from an AggLayer chain to Ethereum (network id 0)
interface IAggLayerBridge {
  /// @notice Emitted when an asset or message is bridged out of this network
  /// @param leafType 0 for assets, 1 for messages
  /// @param originNetwork Network id the token is native to
  /// @param originAddress Token address on its origin network
  /// @param destinationNetwork Network id the asset is being bridged to
  /// @param destinationAddress Recipient on the destination network
  /// @param amount Amount bridged
  /// @param metadata Token metadata (name, symbol, decimals) when first bridging a native token
  /// @param depositCount Index of the new leaf in this network's local exit tree
  event BridgeEvent(
    uint8 leafType,
    uint32 originNetwork,
    address originAddress,
    uint32 destinationNetwork,
    address destinationAddress,
    uint256 amount,
    bytes metadata,
    uint32 depositCount
  );

  /// @notice Bridges `amount` of `token` to `destinationAddress` on `destinationNetwork`
  /// @dev A wrapped token minted by this bridge is burned from the caller directly, without an
  /// allowance. Any other ERC20 is pulled with `transferFrom` and escrowed on this network.
  /// `msg.value` must be zero unless `token` is the zero address (this network's gas token).
  /// Reverts if `destinationNetwork` is this network or the bridge is in emergency state.
  /// @param destinationNetwork AggLayer network id of the destination (0 is Ethereum)
  /// @param destinationAddress Recipient on the destination network
  /// @param amount Amount of tokens to bridge
  /// @param token Token to bridge on this network, or the zero address for the gas token
  /// @param forceUpdateGlobalExitRoot Whether to push the new local exit root to the global exit
  /// root manager in this call, so the deposit can be claimed as soon as it settles
  /// @param permitData Optional EIP-2612 permit calldata, only used for non-wrapped tokens
  function bridgeAsset(
    uint32 destinationNetwork,
    address destinationAddress,
    uint256 amount,
    address token,
    bool forceUpdateGlobalExitRoot,
    bytes calldata permitData
  ) external payable;

  /// @notice AggLayer network id of the network this bridge is deployed on (0 on Ethereum)
  function networkID() external view returns (uint32);

  /// @notice Origin network and origin token of a wrapped token known to this bridge
  /// @dev Both return values are zero if `wrappedToken` is not a wrapped token of this bridge
  /// @param wrappedToken The wrapped token address on this network
  /// @return originNetwork Network id the underlying token is native to
  /// @return originTokenAddress Underlying token address on `originNetwork`
  function wrappedTokenToTokenInfo(address wrappedToken)
    external
    view
    returns (uint32 originNetwork, address originTokenAddress);

  /// @notice Wrapped token on this network for `originTokenAddress` from `originNetwork`
  /// @dev Returns the zero address if the token has never been bridged to this network
  /// @param originNetwork Network id the token is native to
  /// @param originTokenAddress Token address on `originNetwork`
  /// @return The wrapped token address on this network
  function getTokenWrappedAddress(uint32 originNetwork, address originTokenAddress)
    external
    view
    returns (address);
}
