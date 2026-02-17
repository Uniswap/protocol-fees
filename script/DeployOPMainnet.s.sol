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

  /// @dev CrossChainAccount for OP Mainnet
  /// https://optimistic.etherscan.io/address/0xa1dD330d602c32622AA270Ea73d078B803Cb3518
  function _owner() internal pure override returns (address) {
    return 0xa1dD330d602c32622AA270Ea73d078B803Cb3518;
  }

  /// @dev Uniswap V3 Factory on OP Mainnet
  /// https://optimistic.etherscan.io/address/0x1F98431c8aD98523631AE4a59f267346ea31F984
  function _v3Factory() internal pure override returns (address) {
    return 0x1F98431c8aD98523631AE4a59f267346ea31F984;
  }

  /// @dev Bridged UNI on OP Mainnet
  function _resource() internal pure override returns (address) {
    return 0x6fd9d7AD17242c41f7131d257212c54A0e816691;
  }
}
