// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {OPStackDeployer} from "./deployers/OPStackDeployer.sol";

/// @title DeployOPMainnet
/// @notice Deployment script for OP Mainnet (Chain ID: 10)
contract DeployOPMainnet is Script {
  // OP Mainnet chain ID
  uint256 public constant CHAIN_ID = 10;

  // Bridged UNI token on OP Mainnet
  address public constant RESOURCE = 0x6fd9d7AD17242c41f7131d257212c54A0e816691;

  // UNI threshold for release
  uint256 public constant THRESHOLD = 2000e18;

  // UNI Timelock alias (same for all OP Stack chains)
  // L1: 0x1a9C8182C09F50C8318d769245beA52c32BE35BC + 0x1111000000000000000000000000000000001111
  address public constant OWNER = 0x2BAD8182C09F50c8318d769245beA52C32Be46CD;

  function setUp() public {}

  function run() public {
    require(block.chainid == CHAIN_ID, "Not OP Mainnet");

    vm.startBroadcast();

    OPStackDeployer deployer =
      new OPStackDeployer{salt: bytes32(uint256(1))}(RESOURCE, THRESHOLD, OWNER);

    console2.log("=== OP Mainnet Deployment ===");
    console2.log("Deployer:", address(deployer));
    console2.log("TOKEN_JAR:", address(deployer.TOKEN_JAR()));
    console2.log("RELEASER:", address(deployer.RELEASER()));

    vm.stopBroadcast();
  }
}
