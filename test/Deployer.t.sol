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
import {IUNIMinter} from "../src/interfaces/IUNIMinter.sol";

import {console} from "forge-std/console.sol";

contract DeployerTest is Test {
  Deployer public deployer;

  IUniswapV3Factory public factory;

  IAssetSink public assetSink;
  IReleaser public releaser;
  IV3FeeController public feeController;

  address public owner;

  function setUp() public {
    factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    IUniswapV3Factory _factory = UniswapV3FactoryDeployer.deploy();
    vm.etch(address(factory), address(_factory).code);

    owner = makeAddr("owner");
    vm.prank(factory.owner());
    factory.setOwner(owner);

    /// Set the fee tiers on the factory.
    vm.startPrank(owner);
    factory.enableFeeAmount(100, 1);
    factory.enableFeeAmount(500, 10);
    factory.enableFeeAmount(3000, 60);
    factory.enableFeeAmount(10_000, 200);
    vm.stopPrank();

    deployer = new Deployer();

    assetSink = deployer.ASSET_SINK();
    releaser = deployer.RELEASER();
    feeController = deployer.FEE_CONTROLLER();
  }

  function test_deployer_assetSink_setUp() public view {
    assertEq(IOwned(address(assetSink)).owner(), factory.owner());
    assertEq(assetSink.releaser(), address(releaser));
  }

  function test_deployer_releaser_setUp() public view {
    assertEq(IOwned(address(releaser)).owner(), factory.owner());
    assertEq(releaser.thresholdSetter(), factory.owner());
    assertEq(releaser.threshold(), 69_420);
    assertEq(address(releaser.ASSET_SINK()), address(assetSink));
    assertEq(releaser.RESOURCE_RECIPIENT(), address(0xdead));
    assertEq(address(releaser.RESOURCE()), address(0x1000000000000000000000000000000000000000));
  }

  function test_deployer_feeController_setUp() public view {
    assertEq(IOwned(address(feeController)).owner(), factory.owner());
    assertEq(feeController.feeSetter(), factory.owner());
    assertEq(address(feeController.ASSET_SINK()), address(assetSink));
    assertEq(address(feeController.FACTORY()), address(factory));
  }

  function test_deployer_uniMinter_setUp() public view {
    IUNIMinter uniMinter = deployer.UNI_MINTER();
    assertEq(IOwned(address(uniMinter)).owner(), factory.owner());
    assertEq(address(uniMinter.UNI()), 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
  }
}
