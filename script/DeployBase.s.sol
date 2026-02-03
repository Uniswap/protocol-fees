// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {OPStackDeployer} from "./deployers/OPStackDeployer.sol";

/// @title DeployBase
/// @notice Deployment script for Base (Chain ID: 8453)
contract DeployBase is Script {
  // Base chain ID
  uint256 public constant CHAIN_ID = 8453;

  // Bridged UNI token on Base
  // https://basescan.org/address/0xc3de830ea07524a0761646a6a4e4be0e114a3c83
  address public constant RESOURCE = 0xc3De830EA07524a0761646a6a4e4be0e114a3C83;

  // UNI threshold for release
  uint256 public constant THRESHOLD = 2000e18;

  // UNI Timelock alias (same for all OP Stack chains)
  // L1: 0x1a9C8182C09F50C8318d769245beA52c32BE35BC + 0x1111000000000000000000000000000000001111
  address public constant OWNER = 0x2BAD8182C09F50c8318d769245beA52C32Be46CD;

  function setUp() public {}

  function run() public {
    require(block.chainid == CHAIN_ID, "Not Base");

    vm.startBroadcast();

    OPStackDeployer deployer =
      new OPStackDeployer{salt: bytes32(uint256(1))}(RESOURCE, THRESHOLD, OWNER);

    console2.log("=== Base Deployment ===");
    console2.log("Deployer:", address(deployer));
    console2.log("TOKEN_JAR:", address(deployer.TOKEN_JAR()));
    console2.log("RELEASER:", address(deployer.RELEASER()));

    vm.stopBroadcast();
  }
}
