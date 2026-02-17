// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployOPStackChain} from "./DeployOPStackChain.s.sol";

/// @notice Deployment script for World Chain (Chain ID: 480)
contract DeployWorldchain is DeployOPStackChain {
  function _chainId() internal pure override returns (uint256) {
    return 480;
  }

  function _name() internal pure override returns (string memory) {
    return "World Chain";
  }

  /// @dev CrossChainAccount for Worldchain (existing, used by v3 factory governance)
  /// https://worldscan.org/address/0xcb2436774c3e191c85056d248ef4260ce5f27a9d
  function _owner() internal pure override returns (address) {
    return 0xcb2436774C3e191c85056d248EF4260ce5f27A9D;
  }

  /// @dev Uniswap V3 Factory on Worldchain
  /// https://worldscan.org/address/0x7a5028BDa40e7B173C278C5342087826455ea25a
  function _v3Factory() internal pure override returns (address) {
    return 0x7a5028BDa40e7B173C278C5342087826455ea25a;
  }

  /// @dev Bridged UNI is not yet deployed, will be created via OptimismMintableERC20Factory
  function _resource() internal pure override returns (address) {
    return address(0);
  }
}
