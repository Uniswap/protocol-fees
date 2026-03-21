// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployOPStackChain} from "../shared/DeployOPStackChain.s.sol";

/// @notice Deployment script for X Layer (Chain ID: 196)
contract DeployXLayer is DeployOPStackChain {
  function _chainId() internal pure override returns (uint256) {
    return 196;
  }

  function _name() internal pure override returns (string memory) {
    return "X Layer";
  }

  /// @dev Uniswap V3 Factory on X Layer
  /// https://www.oklink.com/xlayer/address/0x4B2ab38DBF28D31D467aA8993f6c2585981D6804
  function _v3Factory() internal pure override returns (address) {
    return 0x4B2ab38DBF28D31D467aA8993f6c2585981D6804;
  }

  /// @dev Bridged UNI is not yet deployed, will be created via OptimismMintableERC20Factory
  function _resource() internal pure override returns (address) {
    return address(0);
  }
}
