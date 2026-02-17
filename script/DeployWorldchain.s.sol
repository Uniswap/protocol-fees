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

  /// @dev Bridged UNI is not yet deployed, will be created via OptimismMintableERC20Factory
  function _resource() internal pure override returns (address) {
    return address(0);
  }
}
