// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {V4UnichainDeployer} from "./deployers/V4UnichainDeployer.sol";

/// @title DeployV4Unichain
/// @notice Deployment script for V4FeeAdapter on Unichain
contract DeployV4Unichain is Script {
  function setUp() public {}

  function run() public {
    require(block.chainid == 130, "Not Unichain");

    vm.startBroadcast();

    V4UnichainDeployer deployer = new V4UnichainDeployer{salt: bytes32(uint256(2))}();
    console2.log("Deployed V4UnichainDeployer at:", address(deployer));
    console2.log("V4_FEE_ADAPTER at:", address(deployer.V4_FEE_ADAPTER()));

    vm.stopBroadcast();
  }
}
