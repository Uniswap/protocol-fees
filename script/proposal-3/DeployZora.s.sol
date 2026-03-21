// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployOPStackChain} from "../shared/DeployOPStackChain.s.sol";

/// @notice Deployment script for Zora (Chain ID: 7777777)
contract DeployZora is DeployOPStackChain {
  function _chainId() internal pure override returns (uint256) {
    return 7_777_777;
  }

  function _name() internal pure override returns (string memory) {
    return "Zora";
  }

  /// @dev CrossChainAccount for Zora (existing, used by v3 factory governance)
  /// https://explorer.zora.energy/address/0x36eEC182D0B24Df3DC23115D64DB521A93D5154f
  function _owner() internal pure override returns (address) {
    return 0x36eEC182D0B24Df3DC23115D64DB521A93D5154f;
  }

  /// @dev Uniswap V3 Factory on Zora
  /// https://explorer.zora.energy/address/0x7145F8aeef1f6510E92164038E1B6F8cB2c42Cbb
  function _v3Factory() internal pure override returns (address) {
    return 0x7145F8aeef1f6510E92164038E1B6F8cB2c42Cbb;
  }

  /// @dev Bridged UNI is not yet deployed, will be created via OptimismMintableERC20Factory
  function _resource() internal pure override returns (address) {
    return address(0);
  }
}
