// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Deployer} from "../src/Deployer.sol";
import {IUniswapV2Factory} from "briefcase/protocols/v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV3Factory} from "briefcase/protocols/v3-core/interfaces/IUniswapV3Factory.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract UnificationProposal is Script {
  IERC20 UNI = IERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
  IUniswapV2Factory public V2_FACTORY =
    IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
  IUniswapV3Factory public constant V3_FACTORY =
    IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
  address public constant OLD_FEE_TO_SETTER = 0x18e433c7Bf8A2E1d0197CE5d8f9AFAda1A771360;

  function setUp() public {}

  function run() public {
    runDeployed(new Deployer());
  }

  function runDeployed(Deployer deployer) public {
    vm.startBroadcast();
    _run(deployer);
    vm.stopBroadcast();
  }

  function runPranked(Deployer deployer) public {
    vm.startPrank(V3_FACTORY.owner());
    _run(deployer);
    vm.stopPrank();
  }

  function _run(Deployer deployer) public {
    address timelock = deployer.V3_FACTORY().owner();

    // Burn 100M UNI
    UNI.transfer(address(0xdead), 100_000_000 ether);
    // Enable UniswapV3 FeeAdapter
    V3_FACTORY.setOwner(address(deployer.V3_FEE_ADAPTER()));
    // Make governance timelock the feeToSetter for UniswapV2
    IFeeToSetter(OLD_FEE_TO_SETTER).setFeeToSetter(timelock);
    // Set TokenJar as the UniswapV2 fee recipient
    V2_FACTORY.setFeeTo(address(deployer.TOKEN_JAR()));
    // Approve 40M UNI to UNIVesting contract
    UNI.approve(address(deployer.UNI_VESTING()), 40_000_000 ether);
  }
}

// interface for:
// https://etherscan.io/address/0x18e433c7Bf8A2E1d0197CE5d8f9AFAda1A771360#code
// the current V2_FACTORY.feeToSetter()
interface IFeeToSetter {
  function setFeeToSetter(address) external;
}
