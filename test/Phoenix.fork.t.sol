// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {
  UniswapV3FactoryDeployer,
  IUniswapV3Factory
} from "briefcase/deployers/v3-core/UniswapV3FactoryDeployer.sol";
import {Deployer} from "../src/Deployer.sol";
import {IAssetSink} from "../src/interfaces/IAssetSink.sol";
import {IReleaser} from "../src/interfaces/IReleaser.sol";
import {IOwned} from "../src/interfaces/base/IOwned.sol";
import {IV3FeeController} from "../src/interfaces/IV3FeeController.sol";

contract PhoenixForkTest is Test {
  Deployer public deployer;

  IUniswapV3Factory public factory;

  IAssetSink public assetSink;
  IReleaser public releaser;
  IV3FeeController public feeController;

  address public owner;

  function setUp() public {
    vm.createSelectFork("mainnet");
    factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    owner = factory.owner();

    deployer = new Deployer();

    assetSink = deployer.ASSET_SINK();
    releaser = deployer.RELEASER();
    feeController = deployer.FEE_CONTROLLER();
  }

  function test_enableFeeV3() public {}
  function test_enableFeeV2() public {}

  function test_collectFeeV3() public {
    test_enableFeeV3();
  }

  function test_releaseV3() public {
    test_collectFeeV3();
  }

  function test_releaseV2V3() public {
    test_enableFeeV2();
  }
}
