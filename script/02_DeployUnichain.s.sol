// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {UnichainDeployer} from "./deployers/UnichainDeployer.sol";
import {OptimismBridgedResourceFirepit} from "../src/releasers/OptimismBridgedResourceFirepit.sol";

contract DeployUnichain is Script {
  function setUp() public {}

  function run() public {
    require(block.chainid == 130, "Not Unichain");

    vm.startBroadcast();

    UnichainDeployer deployer = new UnichainDeployer{salt: bytes32(uint256(1))}();
    console2.log("Deployed Deployer at:", address(deployer));
    console2.log("TOKEN_JAR at:", address(deployer.TOKEN_JAR()));
    console2.log("RELEASER at:", address(deployer.RELEASER()));

    vm.stopBroadcast();
  }
}
