// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployOPStackChain} from "./DeployOPStackChain.s.sol";

/// @notice Deployment script for Soneium (Chain ID: 1868)
contract DeploySoneium is DeployOPStackChain {
  function _chainId() internal pure override returns (uint256) {
    return 1868;
  }

  function _name() internal pure override returns (string memory) {
    return "Soneium";
  }

  /// @dev Uniswap V3 Factory on Soneium
  /// https://soneium.blockscout.com/address/0x42ae7ec7ff020412639d443e245d936429fbe717
  function _v3Factory() internal pure override returns (address) {
    return 0x42aE7Ec7ff020412639d443E245D936429Fbe717;
  }

  /// @dev Bridged UNI is not yet deployed, will be created via OptimismMintableERC20Factory
  function _resource() internal pure override returns (address) {
    return address(0);
  }
}
