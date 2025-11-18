// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MainnetDeployer} from "./deployers/MainnetDeployer.sol";
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

  function run(MainnetDeployer deployer) public {
    vm.startBroadcast();
    _run(deployer);
    vm.stopBroadcast();
  }

  function runPranked(MainnetDeployer deployer) public {
    vm.startPrank(V3_FACTORY.owner());
    _run(deployer);
    vm.stopPrank();
  }

  function _run(MainnetDeployer deployer) public {
    address timelock = deployer.V3_FACTORY().owner();

    // Burn 100M UNI
    UNI.transfer(address(0xdead), 100_000_000 ether);
    /// Set the owner of the v3 factory to the configured fee controller
    V3_FACTORY.setOwner(address(deployer.V3_FEE_ADAPTER()));
    /// Update the v2 fee to setter to the timelock
    IFeeToSetter(OLD_FEE_TO_SETTER).setFeeToSetter(timelock);
    /// Set the recipient of v2 protocol fees to the token jar
    V2_FACTORY.setFeeTo(address(deployer.TOKEN_JAR()));
    /// Approve two years of vesting to the UNIvester smart contract UNI stays in treasury until
    /// vested and unvested UNI can be cancelled by setting approve back to 0
    UNI.approve(address(deployer.UNI_VESTING()), 40_000_000 ether);
  }
}

// interface for:
// https://etherscan.io/address/0x18e433c7Bf8A2E1d0197CE5d8f9AFAda1A771360#code
// the current V2_FACTORY.feeToSetter()
interface IFeeToSetter {
  function setFeeToSetter(address) external;
}
