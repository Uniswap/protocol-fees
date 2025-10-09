// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
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

    // set the fee controller on the v3 factory
    vm.prank(owner);
    factory.setOwner(address(feeController));
  }

  function test_enableFeeV3() public {
    assertEq(feeController.feeSetter(), owner);
    vm.prank(owner);
    feeController.setDefaultFeeByFeeTier(100, 5 << 4 | 5);

    // feeController.setMerkleRoot();
    // feeController.triggerFeeUpdate();
  }

  function test_enableFeeV2() public {}

  function test_collectFeeV3() public {
    test_enableFeeV3();

    // swap on 5 bip pool
    // swap on 30 bip pool
    // swap on 1% pool

    IV3FeeController.CollectParams[] memory params = new IV3FeeController.CollectParams[](1);
    params[0] = IV3FeeController.CollectParams({
      pool: 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8,
      amount0Requested: 0,
      amount1Requested: 0
    });
    feeController.collect(params);
  }

  function test_releaseV3(address caller) public {
    test_collectFeeV3();

    deal(deployer.RESOURCE(), address(caller), releaser.threshold());
    assertEq(IERC20(deployer.RESOURCE()).balanceOf(address(caller)), releaser.threshold());

    vm.prank(caller);
    IERC20(deployer.RESOURCE()).approve(address(releaser), releaser.threshold());
  }

  function test_releaseV2V3() public {
    test_enableFeeV2();
  }
}
