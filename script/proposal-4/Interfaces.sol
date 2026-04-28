// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Governor Bravo
/// @dev For governance call.
interface IGovernorBravo {
  function propose(
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory description
  ) external returns (uint256);
}

/// @title Wormhole Sender
/// @dev For Ethereum -> Celo
interface IWormholeSender {
  function sendMessage(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory datas,
    address wormhole,
    uint16 chainId
  ) external;
}

/// @title Wormhole Core
/// @dev For NttManager configuration.
interface IWormhole {
  function messageFee() external view returns (uint256);
}

/// @title Uni V2 Factory
/// @dev For V2 fee activation
interface IUniswapV2Factory {
  function setFeeToSetter(address) external;
  function setFeeTo(address) external;
}

/// @title Uni V3 Factory
/// @dev For V3 fee activation
interface IUniswapV3Factory {
  function setOwner(address) external;
}

/// @title Uni V4 Pool Manager
/// @dev For ownership transfer
interface IUniswapV4PoolManager {
  function transferOwnership(address) external;
}

/// @title Polygon Fx Root
/// @dev For Ethereum -> Polygon
interface IPolygonFxRoot {
  function sendMessageToChild(address receiver, bytes calldata data) external;
}

/// @title Layer Zero Endpoint
/// @dev For Ethereum -> Avalanche
interface ILayerZeroEndpoint {
  function send(
    uint16 destChainId,
    bytes calldata dest,
    bytes calldata payload,
    address payable refundAddress,
    address zroPaymentAddress,
    bytes calldata adapterParams
  ) external;
}
