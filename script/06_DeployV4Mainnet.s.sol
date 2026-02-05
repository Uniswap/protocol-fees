// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {V4MainnetDeployer} from "./deployers/V4MainnetDeployer.sol";

/// @title DeployV4Mainnet
/// @notice Deployment script for V4FeeAdapter on Ethereum mainnet
contract DeployV4Mainnet is Script {
  function setUp() public {}

  function run() public {
    require(block.chainid == 1, "Not mainnet");

    vm.startBroadcast();

    V4MainnetDeployer deployer = new V4MainnetDeployer{salt: bytes32(uint256(2))}();
    console2.log("Deployed V4MainnetDeployer at:", address(deployer));
    console2.log("V4_FEE_ADAPTER at:", address(deployer.V4_FEE_ADAPTER()));

    vm.stopBroadcast();
  }
}
