// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import "forge-std/Script.sol";
import {MainnetDeployer} from "./deployers/MainnetDeployer.sol";

contract DeployMainnet is Script {
  function setUp() public {}

  function run() public {
    require(block.chainid == 1, "Not mainnet");

    vm.startBroadcast();

    MainnetDeployer deployer = new MainnetDeployer{salt: bytes32(uint256(1))}();
    console2.log("Deployed Deployer at:", address(deployer));
    console2.log("TOKEN_JAR at:", address(deployer.TOKEN_JAR()));
    console2.log("RELEASER at:", address(deployer.RELEASER()));
    console2.log("V3_FEE_ADAPTER at:", address(deployer.V3_FEE_ADAPTER()));
    console2.log("UNI_VESTING at:", address(deployer.UNI_VESTING()));

    vm.stopBroadcast();
  }
}
