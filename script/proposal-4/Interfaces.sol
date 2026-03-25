// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// re-export to try & keep imports cleaner
import {IBridgehub} from "./ZkSync.sol";

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

/// @title Optimism L1 -> L2 Portal
/// @dev For Ethereum -> Celo
interface IOptimismPortal {
    function depositTransaction(
        address target,
        uint256 value,
        uint64 gasLimit,
        bool isCreation,
        bytes memory data
    ) external payable;
}

/// @title Uni V2 Factory
/// @dev For V2 fee activation
interface IUniswapV2Factory {
  function setFeeTo(address) external;
}

/// @title Uni V3 Factory
/// @dev For V3 fee activation
interface IUniswapV3Factory {
  function setOwner(address) external;
}
