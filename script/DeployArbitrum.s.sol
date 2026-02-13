// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {ArbitrumDeployer} from "./deployers/ArbitrumDeployer.sol";
import {IOwned} from "../src/interfaces/base/IOwned.sol";
import {IResourceManager} from "../src/interfaces/base/IResourceManager.sol";

/// @title DeployArbitrum
/// @notice Deployment script for Arbitrum One (Chain ID: 42161)
contract DeployArbitrum is Script {
  error WrongChain();

  // Arbitrum One chain ID
  uint256 public constant CHAIN_ID = 42_161;

  // Bridged UNI token on Arbitrum One
  // https://arbiscan.io/token/0xfa7f8980b0f1e64a2062791cc3b0871572f1f7f0
  address public constant RESOURCE = 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0;

  // L1 UNI token on Ethereum mainnet
  // https://etherscan.io/token/0x1f9840a85d5af5bf1d1762f925bdaddc4201f984
  address public constant L1_RESOURCE = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

  // UNI threshold for release
  uint256 public constant THRESHOLD = 2000e18;

  // UNI Timelock alias for Arbitrum
  // L1 Timelock: 0x1a9C8182C09F50C8318d769245beA52c32BE35BC
  // Arbitrum alias offset: 0x1111000000000000000000000000000000001111
  // Result: 0x2BAD8182C09F50c8318d769245beA52C32Be46CD
  address public constant OWNER = 0x2BAD8182C09F50c8318d769245beA52C32Be46CD;

  function setUp() public {}

  function run() public {
    require(block.chainid == CHAIN_ID, WrongChain());

    vm.startBroadcast();

    ArbitrumDeployer deployer =
      new ArbitrumDeployer{salt: bytes32(uint256(1))}(RESOURCE, L1_RESOURCE, THRESHOLD, OWNER);

    console2.log("=== Arbitrum One Deployment ===");
    console2.log("Deployer:", address(deployer));
    console2.log("TOKEN_JAR:", address(deployer.TOKEN_JAR()));
    console2.log("RELEASER:", address(deployer.RELEASER()));

    vm.stopBroadcast();

    // Post-deployment assertions
    assert(deployer.TOKEN_JAR().releaser() == address(deployer.RELEASER()));
    assert(IOwned(address(deployer.TOKEN_JAR())).owner() == OWNER);
    assert(IResourceManager(address(deployer.RELEASER())).thresholdSetter() == OWNER);
    assert(IOwned(address(deployer.RELEASER())).owner() == OWNER);
  }
}
