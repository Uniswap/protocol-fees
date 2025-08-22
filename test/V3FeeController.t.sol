// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {PhoenixTestBase} from "./utils/PhoenixTestBase.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {
  UniswapV3FactoryDeployer,
  IUniswapV3Factory
} from "briefcase/deployers/v3-core/UniswapV3FactoryDeployer.sol";
import {Merkle} from "murky/src/Merkle.sol";
import {V3FeeController} from "../src/feeControllers/V3FeeController.sol";

contract V3FeeControllerTest is PhoenixTestBase {
  IUniswapV3Factory public factory;

  V3FeeController public feeController;

  uint160 public constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

  address pool;

  Merkle merkle;

  uint256 slot = 3;

  struct ProtocolFees {
    uint128 token0;
    uint128 token1;
  }

  function setUp() public override {
    super.setUp();

    factory = UniswapV3FactoryDeployer.deploy();

    feeController = new V3FeeController(address(factory), address(assetSink), factory.owner());

    /// Transfer ownership to the fee controller.
    vm.prank(factory.owner());
    factory.setOwner(address(feeController));

    // Create pool.
    pool = factory.createPool(address(mockToken), address(mockToken1), 3000);
    IUniswapV3Pool(pool).initialize(SQRT_PRICE_1_1);

    // Mint tokens.
    mockToken.mint(address(pool), INITIAL_TOKEN_AMOUNT);
    mockToken1.mint(address(pool), INITIAL_TOKEN_AMOUNT);

    merkle = new Merkle();
  }

  function test_feeController_isOwner() public {
    assertEq(address(factory.owner()), address(feeController));
  }

  function test_assetSink_isSet() public view {
    assertEq(feeController.FEE_SINK(), address(assetSink));
  }

  function test_collect_full_success() public {
    uint128 amount0 = 10e18;
    uint128 amount1 = 11e18;

    address token0 =
      address(mockToken) < address(mockToken1) ? address(mockToken) : address(mockToken1);
    address token1 =
      address(mockToken) < address(mockToken1) ? address(mockToken1) : address(mockToken);

    _mockSetProtocolFees(amount0, amount1);

    V3FeeController.CollectParams[] memory collectParams = new V3FeeController.CollectParams[](1);
    collectParams[0] = V3FeeController.CollectParams({
      pool: pool,
      amount0Requested: amount0,
      amount1Requested: amount1
    });

    uint256 balanceBefore = MockERC20(token0).balanceOf(address(assetSink));
    uint256 balanceBefore1 = MockERC20(token1).balanceOf(address(assetSink));

    // Anyone can call collect.
    V3FeeController.Collected[] memory collected = feeController.collect(collectParams);

    // Note that 1 wei is left in the pool.
    assertEq(collected[0].amount0Collected, amount0 - 1);
    assertEq(collected[0].amount1Collected, amount1 - 1);

    // Phoenix Test Base pre-funds asset sink, and poolManager sends more funds to it
    assertEq(MockERC20(token0).balanceOf(address(assetSink)), balanceBefore + amount0 - 1);
    assertEq(MockERC20(token1).balanceOf(address(assetSink)), balanceBefore1 + amount1 - 1);
  }

  /// Test spoofed storage setting in UniswapV3Pool.
  function test_protocolFees_set() public {
    (uint128 token0, uint128 token1) = IUniswapV3Pool(pool).protocolFees();
    assertEq(token0, 0);
    assertEq(token1, 0);

    uint128 protocolFee0 = 1e18;
    uint128 protocolFee1 = 3e18;

    _mockSetProtocolFees(protocolFee0, protocolFee1);

    (token0, token1) = IUniswapV3Pool(pool).protocolFees();
    assertEq(token0, protocolFee0);
    assertEq(token1, protocolFee1);
  }

  function _mockSetProtocolFees(uint128 token0, uint128 token1) internal {
    uint256 toSet = uint256(token1) << 128 | uint256(token0);
    vm.store(pool, bytes32(slot), bytes32(toSet));
  }
}
