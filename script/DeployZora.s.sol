// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployOPStackChain} from "./DeployOPStackChain.s.sol";

/// @notice Deployment script for Zora (Chain ID: 7777777)
contract DeployZora is DeployOPStackChain {
  function _chainId() internal pure override returns (uint256) {
    return 7_777_777;
  }

  function _name() internal pure override returns (string memory) {
    return "Zora";
  }

  /// @dev Bridged UNI is not yet deployed, will be created via OptimismMintableERC20Factory
  function _resource() internal pure override returns (address) {
    return address(0);
  }
}
