// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import "forge-std/Script.sol";
import {V3OpenMainnetDeployer} from "./deployers/V3OpenMainnetDeployer.sol";

contract DeployV3OpenMainnet is Script {
  function setUp() public {}

  function run() public {
    require(block.chainid == 1, "Not mainnet");

    vm.startBroadcast();

    V3OpenMainnetDeployer deployer = new V3OpenMainnetDeployer{salt: bytes32(uint256(1))}();
    console2.log("Deployed Deployer at:", address(deployer));
    console2.log("V3_OPEN_FEE_ADAPTER at:", address(deployer.V3_OPEN_FEE_ADAPTER()));

    vm.stopBroadcast();
  }
}
