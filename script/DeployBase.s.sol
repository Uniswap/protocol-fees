// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployOPStackChain} from "./DeployOPStackChain.s.sol";

/// @title DeployBase
/// @notice Deployment script for Base (Chain ID: 8453)
contract DeployBase is DeployOPStackChain {
  function _chainId() internal pure override returns (uint256) {
    return 8453;
  }

  function _name() internal pure override returns (string memory) {
    return "Base";
  }

  /// @dev CrossChainAccount for Base
  /// https://basescan.org/address/0x31FAfd4889FA1269F7a13A66eE0fB458f27D72A9
  function _owner() internal pure override returns (address) {
    return 0x31FAfd4889FA1269F7a13A66eE0fB458f27D72A9;
  }

  /// @dev Bridged UNI on Base
  /// https://basescan.org/address/0xc3de830ea07524a0761646a6a4e4be0e114a3c83
  function _resource() internal pure override returns (address) {
    return 0xc3De830EA07524a0761646a6a4e4be0e114a3C83;
  }
}
