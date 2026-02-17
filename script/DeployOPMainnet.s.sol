// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployOPStackChain} from "./DeployOPStackChain.s.sol";

/// @title DeployOPMainnet
/// @notice Deployment script for OP Mainnet (Chain ID: 10)
contract DeployOPMainnet is DeployOPStackChain {
  function _chainId() internal pure override returns (uint256) {
    return 10;
  }

  function _name() internal pure override returns (string memory) {
    return "OP Mainnet";
  }

  /// @dev Bridged UNI on OP Mainnet
  function _resource() internal pure override returns (address) {
    return 0x6fd9d7AD17242c41f7131d257212c54A0e816691;
  }
}
