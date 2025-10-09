// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {
  UniswapV3FactoryDeployer,
  IUniswapV3Factory
} from "briefcase/deployers/v3-core/UniswapV3FactoryDeployer.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {Deployer} from "../src/Deployer.sol";
import {IAssetSink} from "../src/interfaces/IAssetSink.sol";
import {IReleaser} from "../src/interfaces/IReleaser.sol";
import {IOwned} from "../src/interfaces/base/IOwned.sol";
import {IV3FeeController} from "../src/interfaces/IV3FeeController.sol";
import {Merkle} from "murky/src/Merkle.sol";

contract PhoenixForkTest is Test {
  Deployer public deployer;
  IUniswapV3Factory public factory;
  IAssetSink public assetSink;
  IReleaser public releaser;
  IV3FeeController public feeController;

  address public owner;
  Merkle merkle;
  address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address pool0; // 1 bip pool
  address pool1; // 5 bip pool
  address pool2; // 30 bip pool
  address pool3; // 1% pool

  function setUp() public {
    vm.createSelectFork("mainnet");
    factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    owner = factory.owner();

    deployer = new Deployer();
    assetSink = deployer.ASSET_SINK();
    releaser = deployer.RELEASER();
    feeController = deployer.FEE_CONTROLLER();

    merkle = new Merkle();

    // set the fee controller on the v3 factory
    vm.prank(owner);
    factory.setOwner(address(feeController));

    pool0 = factory.getPool(WETH, USDC, 100); // 1 bip pool
    pool1 = factory.getPool(WETH, USDC, 500); // 5 bip pool
    pool2 = factory.getPool(WETH, USDC, 3000); // 30 bip pool
    pool3 = factory.getPool(WETH, USDC, 10_000); // 1% pool
  }

  function test_enableFeeV3() public {
    assertEq(feeController.feeSetter(), owner);
    vm.startPrank(owner);
    feeController.setDefaultFeeByFeeTier(100, 10 << 4 | 10);
    feeController.setDefaultFeeByFeeTier(500, 8 << 4 | 8);
    feeController.setDefaultFeeByFeeTier(3000, 6 << 4 | 6);
    feeController.setDefaultFeeByFeeTier(10_000, 4 << 4 | 4);
    vm.stopPrank();

    // Generate merkle root from leaves
    bytes32 targetLeaf = _hashLeaf(USDC, WETH);
    bytes32 dummyLeaf = _hashLeaf(address(0), address(1));
    bytes32[] memory leaves = new bytes32[](2);
    leaves[0] = targetLeaf;
    leaves[1] = dummyLeaf;
    bytes32 merkleRoot = merkle.getRoot(leaves);

    vm.prank(owner);
    feeController.setMerkleRoot(merkleRoot);

    // Enable fees on the 4 pools
    bytes32[] memory proof = merkle.getProof(leaves, 0);
    feeController.triggerFeeUpdate(USDC, WETH, proof);

    // fees were set correctly
    (,,,,, uint8 protocolFee,) = IUniswapV3Pool(pool0).slot0();
    assertEq(protocolFee, 10 << 4 | 10);
    (,,,,, protocolFee,) = IUniswapV3Pool(pool1).slot0();
    assertEq(protocolFee, 8 << 4 | 8);
    (,,,,, protocolFee,) = IUniswapV3Pool(pool2).slot0();
    assertEq(protocolFee, 6 << 4 | 6);
    (,,,,, protocolFee,) = IUniswapV3Pool(pool3).slot0();
    assertEq(protocolFee, 4 << 4 | 4);
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

  function _hashLeaf(address token0, address token1) internal pure returns (bytes32) {
    return keccak256(abi.encode(keccak256(abi.encode(token0, token1))));
  }
}
