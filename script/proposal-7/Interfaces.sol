// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

/// @title Wormhole Core
/// @dev Queried for the message fee charged when publishing a Wormhole message.
interface IWormhole {
  function messageFee() external view returns (uint256);
}

/// @title Wormhole Transceiver
/// @dev Minimal surface for encoding the Ethereum-side peer registration into the proposal and
/// checking its preconditions. The full contract lives in `lib/native-token-transfers` and
/// compiles under a reduced optimizer profile; the proposal only needs the selector.
interface IWormholeTransceiver {
  function owner() external view returns (address);
  function setWormholePeer(uint16 peerChainId, bytes32 peerContract) external payable;
  function getWormholePeer(uint16 chainId) external view returns (bytes32);
}

/// @title Ntt Manager
/// @dev Minimal surface for encoding the Ethereum-side peer registration into the proposal and
/// checking its preconditions.
interface INttManagerPeers {
  struct NttManagerPeer {
    bytes32 peerAddress;
    uint8 tokenDecimals;
  }

  function owner() external view returns (address);
  function setPeer(uint16 peerChainId, bytes32 peerContract, uint8 decimals, uint256 inboundLimit)
    external;
  function getPeer(uint16 chainId) external view returns (NttManagerPeer memory);
}

/// @title Uniswap Wormhole Message Receiver
/// @dev Minimal surface for the proposal preflight: the Ethereum emitter the receiver trusts and
/// the Wormhole chain id it expects that emitter on.
interface IUniswapWormholeMessageReceiver {
  function messageSender() external view returns (bytes32);
  function ETHEREUM_CHAIN_ID() external view returns (uint16);
}
