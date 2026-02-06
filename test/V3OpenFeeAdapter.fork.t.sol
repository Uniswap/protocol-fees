// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {MainnetDeployer} from "../script/deployers/MainnetDeployer.sol";
import {V3OpenMainnetDeployer} from "../script/deployers/V3OpenMainnetDeployer.sol";
import {V3OpenUnichainDeployer} from "../script/deployers/V3OpenUnichainDeployer.sol";
import {V3OpenFeeAdapterProposal} from "../script/08_V3OpenFeeAdapterProposal.s.sol";
import {UnificationProposal} from "../script/04_UnificationProposal.s.sol";
import {V3OpenFeeAdapter} from "../src/feeAdapters/V3OpenFeeAdapter.sol";
import {IV3OpenFeeAdapter} from "../src/interfaces/IV3OpenFeeAdapter.sol";
import {IV3FeeAdapter} from "../src/interfaces/IV3FeeAdapter.sol";
import {IOwned} from "../src/interfaces/base/IOwned.sol";

/// @notice Fork tests for V3OpenFeeAdapter on Mainnet
contract V3OpenFeeAdapterMainnetForkTest is Test {
  using FixedPointMathLib for uint256;

  MainnetDeployer public mainnetDeployer;
  V3OpenMainnetDeployer public v3OpenDeployer;
  IV3OpenFeeAdapter public v3OpenFeeAdapter;
  IV3FeeAdapter public v3FeeAdapter;

  IUniswapV3Factory public constant V3_FACTORY =
    IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

  address public constant TIMELOCK = 0x1a9C8182C09F50C8318d769245beA52c32BE35BC;

  // Test tokens
  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

  // Real pools
  address public pool_USDC_WETH_500;
  address public pool_USDC_WETH_3000;

  // User for swaps
  address public user = makeAddr("user");

  function setUp() public {
    // Fork mainnet at block before unification proposal
    vm.createSelectFork("mainnet", 24_106_377);
    assertEq(block.chainid, 1, "Not on mainnet");

    // Deploy MainnetDeployer and execute unification proposal
    mainnetDeployer = new MainnetDeployer();
    UnificationProposal unificationProposal = new UnificationProposal();
    unificationProposal.runPranked(mainnetDeployer);
    v3FeeAdapter = mainnetDeployer.V3_FEE_ADAPTER();

    // Deploy V3OpenFeeAdapter
    v3OpenDeployer = new V3OpenMainnetDeployer();
    v3OpenFeeAdapter = v3OpenDeployer.V3_OPEN_FEE_ADAPTER();

    // Get real pool addresses
    pool_USDC_WETH_500 = V3_FACTORY.getPool(USDC, WETH, 500);
    pool_USDC_WETH_3000 = V3_FACTORY.getPool(USDC, WETH, 3000);

    // Execute V3OpenFeeAdapter migration proposal
    V3OpenFeeAdapterProposal v3OpenProposal = new V3OpenFeeAdapterProposal();
    v3OpenProposal.runPranked(v3FeeAdapter, v3OpenFeeAdapter);
  }

  function test_deploymentConfiguration() public view {
    // Verify adapter configuration
    assertEq(address(v3OpenFeeAdapter.FACTORY()), address(V3_FACTORY));
    assertEq(v3OpenFeeAdapter.TOKEN_JAR(), v3OpenDeployer.TOKEN_JAR());
    assertEq(v3OpenFeeAdapter.feeSetter(), TIMELOCK);
    assertEq(IOwned(address(v3OpenFeeAdapter)).owner(), TIMELOCK);

    // Verify factory ownership transferred
    assertEq(V3_FACTORY.owner(), address(v3OpenFeeAdapter));
  }

  function test_feeTierDefaultsConfigured() public view {
    // Verify default fees are set
    assertEq(v3OpenFeeAdapter.defaultFees(100), 4 << 4 | 4); // 1/4
    assertEq(v3OpenFeeAdapter.defaultFees(500), 4 << 4 | 4); // 1/4
    assertEq(v3OpenFeeAdapter.defaultFees(3000), 6 << 4 | 6); // 1/6
    assertEq(v3OpenFeeAdapter.defaultFees(10_000), 6 << 4 | 6); // 1/6
  }

  function test_permissionlessTriggerFeeUpdate() public {
    // Anyone can trigger fee updates (no merkle proof needed)
    address randomCaller = makeAddr("random");

    vm.prank(randomCaller);
    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);

    // Verify fee was set
    (,,,,, uint8 protocolFee,) = IUniswapV3Pool(pool_USDC_WETH_500).slot0();
    assertEq(protocolFee, 4 << 4 | 4, "Fee should be 1/4");
  }

  function test_waterfallResolution_tierDefault() public {
    // Trigger fee update - should use tier default
    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);

    (,,,,, uint8 protocolFee,) = IUniswapV3Pool(pool_USDC_WETH_500).slot0();
    assertEq(protocolFee, 4 << 4 | 4, "Should use tier default");
  }

  function test_waterfallResolution_poolOverride() public {
    // Set pool override
    uint8 poolOverride = 10 << 4 | 10; // 1/10
    vm.prank(TIMELOCK);
    v3OpenFeeAdapter.setPoolOverride(pool_USDC_WETH_500, poolOverride);

    // Trigger fee update - should use pool override
    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);

    (,,,,, uint8 protocolFee,) = IUniswapV3Pool(pool_USDC_WETH_500).slot0();
    assertEq(protocolFee, poolOverride, "Should use pool override");
  }

  function test_waterfallResolution_globalDefault() public {
    uint8 globalDefault = 5 << 4 | 5;

    vm.startPrank(TIMELOCK);
    v3OpenFeeAdapter.clearFeeTierDefault(500);
    v3OpenFeeAdapter.setDefaultFee(globalDefault);
    vm.stopPrank();

    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);

    (,,,,, uint8 protocolFee,) = IUniswapV3Pool(pool_USDC_WETH_500).slot0();
    assertEq(protocolFee, globalDefault, "Should use global default");
  }

  function test_waterfallResolution_zeroPoolOverrideDisablesFees() public {
    // Set tier default first
    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);
    (,,,,, uint8 feeBeforeOverride,) = IUniswapV3Pool(pool_USDC_WETH_500).slot0();
    assertTrue(feeBeforeOverride > 0, "Fee should be set");

    // Set pool override to zero (disable fees)
    vm.prank(TIMELOCK);
    v3OpenFeeAdapter.setPoolOverride(pool_USDC_WETH_500, 0);

    // Trigger fee update - should disable fees
    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);

    (,,,,, uint8 protocolFee,) = IUniswapV3Pool(pool_USDC_WETH_500).slot0();
    assertEq(protocolFee, 0, "Fees should be disabled");
  }

  function test_batchTriggerFeeUpdate() public {
    // Batch update multiple pools
    IV3OpenFeeAdapter.Pair[] memory pairs = new IV3OpenFeeAdapter.Pair[](1);
    pairs[0] = IV3OpenFeeAdapter.Pair({token0: USDC, token1: WETH});

    v3OpenFeeAdapter.batchTriggerFeeUpdate(pairs);

    // Verify both pool tiers were updated
    (,,,,, uint8 fee500,) = IUniswapV3Pool(pool_USDC_WETH_500).slot0();
    (,,,,, uint8 fee3000,) = IUniswapV3Pool(pool_USDC_WETH_3000).slot0();

    assertEq(fee500, 4 << 4 | 4, "500 tier should be 1/4");
    assertEq(fee3000, 6 << 4 | 6, "3000 tier should be 1/6");
  }

  function test_collectProtocolFees() public {
    // Setup: trigger fee update first
    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);

    // Get initial protocol fees
    (uint128 initialFee0, uint128 initialFee1) = IUniswapV3Pool(pool_USDC_WETH_500).protocolFees();

    // If there are fees to collect, collect them
    if (initialFee0 > 0 || initialFee1 > 0) {
      IV3OpenFeeAdapter.CollectParams[] memory params = new IV3OpenFeeAdapter.CollectParams[](1);
      params[0] = IV3OpenFeeAdapter.CollectParams({
        pool: pool_USDC_WETH_500,
        amount0Requested: type(uint128).max,
        amount1Requested: type(uint128).max
      });

      v3OpenFeeAdapter.collect(params);

      // Verify fees were collected to TOKEN_JAR
      // Fees go to TOKEN_JAR, we can verify the pool's protocol fees are reduced
      (uint128 afterFee0, uint128 afterFee1) = IUniswapV3Pool(pool_USDC_WETH_500).protocolFees();
      assertTrue(afterFee0 <= 1 && afterFee1 <= 1, "Fees should be collected");
    }
  }

  function test_clearPoolOverride_fallsBackToTierDefault() public {
    // Set pool override
    uint8 poolOverride = 10 << 4 | 10;
    vm.prank(TIMELOCK);
    v3OpenFeeAdapter.setPoolOverride(pool_USDC_WETH_500, poolOverride);

    // Trigger update with override
    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);
    (,,,,, uint8 feeWithOverride,) = IUniswapV3Pool(pool_USDC_WETH_500).slot0();
    assertEq(feeWithOverride, poolOverride);

    // Clear override
    vm.prank(TIMELOCK);
    v3OpenFeeAdapter.clearPoolOverride(pool_USDC_WETH_500);

    // Trigger update - should fall back to tier default
    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);
    (,,,,, uint8 feeAfterClear,) = IUniswapV3Pool(pool_USDC_WETH_500).slot0();
    assertEq(feeAfterClear, 4 << 4 | 4, "Should fall back to tier default");
  }

  function test_enableNewFeeTier() public {
    // Owner can enable new fee tiers
    uint24 newTier = 200;
    int24 tickSpacing = 4;

    vm.prank(TIMELOCK);
    v3OpenFeeAdapter.enableFeeAmount(newTier, tickSpacing);

    // Verify tier was added
    assertEq(v3OpenFeeAdapter.feeTiers(4), newTier);
  }

  function test_factoryOwnershipCanBeTransferred() public {
    // V3OpenFeeAdapter can transfer factory ownership
    address newOwner = makeAddr("newOwner");

    vm.prank(TIMELOCK);
    v3OpenFeeAdapter.setFactoryOwner(newOwner);

    assertEq(V3_FACTORY.owner(), newOwner);
  }

  // ============ Swap Behavior Tests ============

  function test_swapCollectsCorrectFees_tierDefault() public {
    // Trigger fee update with tier default (1/4 for 500 tier)
    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);

    // Get initial protocol fees
    (uint128 fee0Before, uint128 fee1Before) = IUniswapV3Pool(pool_USDC_WETH_500).protocolFees();

    // Perform a swap
    uint256 swapAmount = 100_000 * 1e6; // 100k USDC
    deal(USDC, address(this), swapAmount);

    bool zeroForOne = USDC < WETH;
    _exactInSwapV3(pool_USDC_WETH_500, zeroForOne, swapAmount);

    // Get protocol fees after swap
    (uint128 fee0After, uint128 fee1After) = IUniswapV3Pool(pool_USDC_WETH_500).protocolFees();

    // Calculate fee accrued
    uint128 feeAccrued = zeroForOne ? fee0After - fee0Before : fee1After - fee1Before;

    // With 500 tier (0.05% LP fee) and 1/4 protocol fee:
    // Expected fee = swapAmount * 0.0005 / 4
    uint256 expectedFee = uint256(swapAmount).mulWadDown(0.0005e18) / 4;
    assertApproxEqAbs(feeAccrued, expectedFee, 1, "Fee should match expected");
  }

  function test_swapCollectsCorrectFees_poolOverride() public {
    // Set pool override to 1/10 (lower than tier default of 1/4)
    uint8 poolOverride = 10 << 4 | 10;
    vm.prank(TIMELOCK);
    v3OpenFeeAdapter.setPoolOverride(pool_USDC_WETH_500, poolOverride);

    // Trigger fee update
    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);

    // Get initial protocol fees
    (uint128 fee0Before, uint128 fee1Before) = IUniswapV3Pool(pool_USDC_WETH_500).protocolFees();

    // Perform a swap
    uint256 swapAmount = 100_000 * 1e6; // 100k USDC
    deal(USDC, address(this), swapAmount);

    bool zeroForOne = USDC < WETH;
    _exactInSwapV3(pool_USDC_WETH_500, zeroForOne, swapAmount);

    // Get protocol fees after swap
    (uint128 fee0After, uint128 fee1After) = IUniswapV3Pool(pool_USDC_WETH_500).protocolFees();

    uint128 feeAccrued = zeroForOne ? fee0After - fee0Before : fee1After - fee1Before;

    // With 500 tier (0.05% LP fee) and 1/10 protocol fee:
    // Expected fee = swapAmount * 0.0005 / 10
    uint256 expectedFee = uint256(swapAmount).mulWadDown(0.0005e18) / 10;
    assertApproxEqAbs(feeAccrued, expectedFee, 1, "Fee should match expected with pool override");
  }

  function test_swapNoFeesWhenZeroOverride() public {
    // Set pool override to 0 (disable fees)
    vm.prank(TIMELOCK);
    v3OpenFeeAdapter.setPoolOverride(pool_USDC_WETH_500, 0);

    // Trigger fee update
    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);

    // Verify protocol fee is 0
    (,,,,, uint8 protocolFee,) = IUniswapV3Pool(pool_USDC_WETH_500).slot0();
    assertEq(protocolFee, 0, "Protocol fee should be 0");

    // Get initial protocol fees
    (uint128 fee0Before, uint128 fee1Before) = IUniswapV3Pool(pool_USDC_WETH_500).protocolFees();

    // Perform a swap
    uint256 swapAmount = 100_000 * 1e6;
    deal(USDC, address(this), swapAmount);

    bool zeroForOne = USDC < WETH;
    _exactInSwapV3(pool_USDC_WETH_500, zeroForOne, swapAmount);

    // Get protocol fees after swap
    (uint128 fee0After, uint128 fee1After) = IUniswapV3Pool(pool_USDC_WETH_500).protocolFees();

    // Fees should not have increased
    assertEq(fee0After, fee0Before, "No fee0 should accrue");
    assertEq(fee1After, fee1Before, "No fee1 should accrue");
  }

  function test_swapFeesCollectedToTokenJar() public {
    // Trigger fee update
    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);

    // First, accumulate some fees
    uint256 swapAmount = 1_000_000 * 1e6; // 1M USDC
    deal(USDC, address(this), swapAmount);

    bool zeroForOne = USDC < WETH;
    _exactInSwapV3(pool_USDC_WETH_500, zeroForOne, swapAmount);

    // Check protocol fees accrued
    (uint128 fee0, uint128 fee1) = IUniswapV3Pool(pool_USDC_WETH_500).protocolFees();
    assertTrue(fee0 > 1 || fee1 > 1, "Should have accrued fees");

    // Get token jar balances before collection
    address tokenJar = v3OpenFeeAdapter.TOKEN_JAR();
    uint256 jarUsdcBefore = IERC20(USDC).balanceOf(tokenJar);
    uint256 jarWethBefore = IERC20(WETH).balanceOf(tokenJar);

    // Collect fees
    IV3OpenFeeAdapter.CollectParams[] memory params = new IV3OpenFeeAdapter.CollectParams[](1);
    params[0] = IV3OpenFeeAdapter.CollectParams({
      pool: pool_USDC_WETH_500,
      amount0Requested: type(uint128).max,
      amount1Requested: type(uint128).max
    });

    v3OpenFeeAdapter.collect(params);

    // Verify tokens arrived at TokenJar
    uint256 jarUsdcAfter = IERC20(USDC).balanceOf(tokenJar);
    uint256 jarWethAfter = IERC20(WETH).balanceOf(tokenJar);

    // At least one token should have increased (depending on swap direction)
    assertTrue(
      jarUsdcAfter > jarUsdcBefore || jarWethAfter > jarWethBefore,
      "Fees should be collected to token jar"
    );
  }

  function test_swapDifferentFeeTiers() public {
    // Test 30 bps tier (1/6 fee)
    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_3000);

    (,,,,, uint8 protocolFee3000,) = IUniswapV3Pool(pool_USDC_WETH_3000).slot0();
    assertEq(protocolFee3000, 6 << 4 | 6, "3000 tier should have 1/6 fee");

    // Perform swap on 3000 tier pool
    uint256 swapAmount = 100_000 * 1e6;
    deal(USDC, address(this), swapAmount);

    (uint128 fee0Before,) = IUniswapV3Pool(pool_USDC_WETH_3000).protocolFees();

    bool zeroForOne = USDC < WETH;
    _exactInSwapV3(pool_USDC_WETH_3000, zeroForOne, swapAmount);

    (uint128 fee0After,) = IUniswapV3Pool(pool_USDC_WETH_3000).protocolFees();

    // With 3000 tier (0.3% LP fee) and 1/6 protocol fee
    // Expected fee = swapAmount * 0.003 / 6
    if (zeroForOne) {
      uint256 expectedFee = uint256(swapAmount).mulWadDown(0.003e18) / 6;
      assertApproxEqAbs(fee0After - fee0Before, expectedFee, 1, "3000 tier fee should match");
    }
  }

  // --- Helpers ---

  function _exactInSwapV3(address pool, bool zeroForOne, uint256 amountIn) internal {
    IUniswapV3Pool(pool).swap(
      address(this),
      zeroForOne,
      int256(amountIn),
      zeroForOne
        ? 4_295_128_739 + 1
        : 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342 - 1,
      abi.encode(address(this))
    );
  }

  function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data)
    external
  {
    address payer = abi.decode(data, (address));
    if (amount0Delta > 0) {
      IERC20 token = IERC20(IUniswapV3Pool(msg.sender).token0());
      vm.prank(payer);
      token.approve(address(this), uint256(amount0Delta));
      token.transferFrom(payer, msg.sender, uint256(amount0Delta));
    } else if (amount1Delta > 0) {
      IERC20 token = IERC20(IUniswapV3Pool(msg.sender).token1());
      vm.prank(payer);
      token.approve(address(this), uint256(amount1Delta));
      token.transferFrom(payer, msg.sender, uint256(amount1Delta));
    }
  }
}

/// @notice Fork tests for V3OpenFeeAdapter on Unichain
contract V3OpenFeeAdapterUnichainForkTest is Test {
  using FixedPointMathLib for uint256;

  V3OpenUnichainDeployer public deployer;
  IV3OpenFeeAdapter public v3OpenFeeAdapter;

  IUniswapV3Factory public constant V3_FACTORY =
    IUniswapV3Factory(0x1F98400000000000000000000000000000000003);

  address public constant OWNER = 0x2BAD8182C09F50c8318d769245beA52C32Be46CD;
  address public constant TOKEN_JAR = 0xD576BDF6b560079a4c204f7644e556DbB19140b5;

  // Unichain tokens
  address public constant WETH = 0x4200000000000000000000000000000000000006;
  address public constant USDC = 0x078D782b760474a361dDA0AF3839290b0EF57AD6;

  // Real pools (resolved in setUp)
  address public pool_USDC_WETH_500;
  address public pool_USDC_WETH_3000;

  function setUp() public {
    vm.createSelectFork("unichain");
    assertEq(block.chainid, 130, "Not on Unichain");

    address currentOwner = V3_FACTORY.owner();

    deployer = new V3OpenUnichainDeployer();
    v3OpenFeeAdapter = deployer.V3_OPEN_FEE_ADAPTER();

    vm.prank(currentOwner);
    V3_FACTORY.setOwner(address(v3OpenFeeAdapter));

    // Resolve real pools
    pool_USDC_WETH_500 = V3_FACTORY.getPool(USDC, WETH, 500);
    pool_USDC_WETH_3000 = V3_FACTORY.getPool(USDC, WETH, 3000);
  }

  function test_deploymentConfiguration() public view {
    assertEq(address(v3OpenFeeAdapter.FACTORY()), address(V3_FACTORY));
    assertEq(v3OpenFeeAdapter.TOKEN_JAR(), TOKEN_JAR);
    assertEq(v3OpenFeeAdapter.feeSetter(), OWNER);
    assertEq(IOwned(address(v3OpenFeeAdapter)).owner(), OWNER);
    assertEq(V3_FACTORY.owner(), address(v3OpenFeeAdapter));
  }

  function test_feeTierDefaultsConfigured() public view {
    assertEq(v3OpenFeeAdapter.defaultFees(100), 4 << 4 | 4);
    assertEq(v3OpenFeeAdapter.defaultFees(500), 4 << 4 | 4);
    assertEq(v3OpenFeeAdapter.defaultFees(3000), 6 << 4 | 6);
    assertEq(v3OpenFeeAdapter.defaultFees(10_000), 6 << 4 | 6);
  }

  function test_permissionlessTriggerFeeUpdate() public {
    if (pool_USDC_WETH_500 == address(0)) return;

    address randomCaller = makeAddr("random");
    vm.prank(randomCaller);
    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);

    (,,,,, uint8 protocolFee,) = IUniswapV3Pool(pool_USDC_WETH_500).slot0();
    assertEq(protocolFee, 4 << 4 | 4, "Fee should be 1/4 for 500 tier");
  }

  function test_waterfallResolution_poolOverride() public {
    if (pool_USDC_WETH_500 == address(0)) return;

    uint8 poolOverride = 8 << 4 | 8;

    vm.prank(OWNER);
    v3OpenFeeAdapter.setPoolOverride(pool_USDC_WETH_500, poolOverride);

    assertEq(v3OpenFeeAdapter.getFee(pool_USDC_WETH_500), poolOverride);

    // Trigger and verify on-chain
    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);
    (,,,,, uint8 protocolFee,) = IUniswapV3Pool(pool_USDC_WETH_500).slot0();
    assertEq(protocolFee, poolOverride);
  }

  function test_waterfallResolution_tierDefault() public {
    if (pool_USDC_WETH_500 == address(0)) return;

    // No override set, should use tier default
    assertEq(v3OpenFeeAdapter.getFee(pool_USDC_WETH_500), 4 << 4 | 4);

    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);
    (,,,,, uint8 protocolFee,) = IUniswapV3Pool(pool_USDC_WETH_500).slot0();
    assertEq(protocolFee, 4 << 4 | 4);
  }

  function test_waterfallResolution_globalDefault() public {
    if (pool_USDC_WETH_500 == address(0)) return;

    uint8 globalDefault = 7 << 4 | 7;

    vm.startPrank(OWNER);
    v3OpenFeeAdapter.setDefaultFee(globalDefault);
    v3OpenFeeAdapter.clearFeeTierDefault(500);
    vm.stopPrank();

    // With tier default cleared, should fall back to global
    assertEq(v3OpenFeeAdapter.getFee(pool_USDC_WETH_500), globalDefault);

    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);
    (,,,,, uint8 protocolFee,) = IUniswapV3Pool(pool_USDC_WETH_500).slot0();
    assertEq(protocolFee, globalDefault);
  }

  function test_clearPoolOverride_fallsBackToTierDefault() public {
    if (pool_USDC_WETH_500 == address(0)) return;

    uint8 poolOverride = 10 << 4 | 10;

    vm.startPrank(OWNER);
    v3OpenFeeAdapter.setPoolOverride(pool_USDC_WETH_500, poolOverride);
    vm.stopPrank();

    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);
    (,,,,, uint8 feeWithOverride,) = IUniswapV3Pool(pool_USDC_WETH_500).slot0();
    assertEq(feeWithOverride, poolOverride);

    vm.prank(OWNER);
    v3OpenFeeAdapter.clearPoolOverride(pool_USDC_WETH_500);

    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);
    (,,,,, uint8 feeAfterClear,) = IUniswapV3Pool(pool_USDC_WETH_500).slot0();
    assertEq(feeAfterClear, 4 << 4 | 4, "Should fall back to tier default");
  }

  function test_zeroPoolOverrideDisablesFees() public {
    if (pool_USDC_WETH_500 == address(0)) return;

    // First set a fee via tier default
    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);
    (,,,,, uint8 feeBefore,) = IUniswapV3Pool(pool_USDC_WETH_500).slot0();
    assertTrue(feeBefore > 0, "Fee should be set");

    // Set pool override to 0 (disable fees)
    vm.prank(OWNER);
    v3OpenFeeAdapter.setPoolOverride(pool_USDC_WETH_500, 0);

    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);
    (,,,,, uint8 feeAfter,) = IUniswapV3Pool(pool_USDC_WETH_500).slot0();
    assertEq(feeAfter, 0, "Fees should be disabled");
  }

  function test_nonOwnerCannotSetFees() public {
    address notOwner = makeAddr("notOwner");

    vm.expectRevert(IV3OpenFeeAdapter.Unauthorized.selector);
    vm.prank(notOwner);
    v3OpenFeeAdapter.setDefaultFee(5 << 4 | 5);
  }

  function test_swapCollectsFees() public {
    if (pool_USDC_WETH_500 == address(0)) return;

    v3OpenFeeAdapter.triggerFeeUpdate(pool_USDC_WETH_500);

    (uint128 fee0Before, uint128 fee1Before) = IUniswapV3Pool(pool_USDC_WETH_500).protocolFees();

    uint256 swapAmount = 10_000 * 1e6;
    deal(USDC, address(this), swapAmount);

    bool zeroForOne = USDC < WETH;
    _exactInSwapV3(pool_USDC_WETH_500, zeroForOne, swapAmount);

    (uint128 fee0After, uint128 fee1After) = IUniswapV3Pool(pool_USDC_WETH_500).protocolFees();

    uint128 feeAccrued = zeroForOne ? fee0After - fee0Before : fee1After - fee1Before;
    uint256 expectedFee = uint256(swapAmount).mulWadDown(0.0005e18) / 4;
    // Allow small rounding tolerance from V3 pool fee math
    assertApproxEqRel(feeAccrued, expectedFee, 0.0001e18, "Fee should match expected");
  }

  // --- Helpers ---

  function _exactInSwapV3(address pool, bool zeroForOne, uint256 amountIn) internal {
    IUniswapV3Pool(pool).swap(
      address(this),
      zeroForOne,
      int256(amountIn),
      zeroForOne
        ? 4_295_128_739 + 1
        : 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342 - 1,
      abi.encode(address(this))
    );
  }

  function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data)
    external
  {
    address payer = abi.decode(data, (address));
    if (amount0Delta > 0) {
      IERC20 token = IERC20(IUniswapV3Pool(msg.sender).token0());
      vm.prank(payer);
      token.approve(address(this), uint256(amount0Delta));
      token.transferFrom(payer, msg.sender, uint256(amount0Delta));
    } else if (amount1Delta > 0) {
      IERC20 token = IERC20(IUniswapV3Pool(msg.sender).token1());
      vm.prank(payer);
      token.approve(address(this), uint256(amount1Delta));
      token.transferFrom(payer, msg.sender, uint256(amount1Delta));
    }
  }
}
