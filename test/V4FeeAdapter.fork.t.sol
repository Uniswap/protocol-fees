// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Deployers} from "../lib/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {V4FeeAdapter, IV4FeeAdapter} from "../src/feeAdapters/V4FeeAdapter.sol";
import {V4FeePolicy, IV4FeePolicy} from "../src/feeAdapters/V4FeePolicy.sol";
import {CurveBreakpoint} from "../src/interfaces/IV4FeePolicy.sol";

/// @notice Integration tests using a real v4 PoolManager (deployed locally via Deployers).
/// Verifies protocol fee accrual from real swaps, collection to TokenJar, and the full
/// adapter + policy waterfall against live pool state.
contract V4FeeAdapterForkTest is Deployers {
  using PoolIdLibrary for PoolKey;
  using StateLibrary for IPoolManager;
  using CurrencyLibrary for Currency;

  V4FeeAdapter adapter;
  V4FeePolicy policy;
  address tokenJar;

  address owner;
  address feeSetter;

  PoolKey pool500; // 5 bps LP fee
  PoolKey pool3000; // 30 bps LP fee
  PoolKey pool10000; // 100 bps LP fee

  uint24 constant PROTO_FEE_100 = (100 << 12) | 100;
  uint24 constant PROTO_FEE_200 = (200 << 12) | 200;
  uint24 constant PROTO_FEE_300 = (300 << 12) | 300;
  uint24 constant PROTO_FEE_500 = (500 << 12) | 500;

  function setUp() public {
    owner = address(this);
    feeSetter = makeAddr("feeSetter");

    // Deploy real v4 PoolManager + routers
    deployFreshManagerAndRouters();
    deployMintAndApprove2Currencies();

    // Use a plain address as the fee destination (avoids TokenJar pragma conflict)
    tokenJar = makeAddr("tokenJar");

    // Deploy adapter + policy
    policy = new V4FeePolicy(manager);
    adapter = new V4FeeAdapter(manager, tokenJar);
    adapter.setPolicy(policy);
    adapter.setFeeSetter(feeSetter);
    policy.setFeeSetter(feeSetter);

    // Register adapter as the protocolFeeController on the real PoolManager
    manager.setProtocolFeeController(address(adapter));

    // Initialize pools with liquidity at different fee tiers.
    // Use explicit tick spacings and aligned tick ranges for each.
    (pool3000,) = initPool(currency0, currency1, IHooks(address(0)), 3000, 60, SQRT_PRICE_1_1);
    (pool500,) = initPool(currency0, currency1, IHooks(address(0)), 500, 10, SQRT_PRICE_1_1);
    (pool10000,) = initPool(currency0, currency1, IHooks(address(0)), 10_000, 200, SQRT_PRICE_1_1);

    // Add liquidity with tick ranges aligned to each pool's tick spacing
    modifyLiquidityRouter.modifyLiquidity(
      pool3000,
      ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100e18, salt: 0}),
      ZERO_BYTES
    );
    modifyLiquidityRouter.modifyLiquidity(
      pool500,
      ModifyLiquidityParams({tickLower: -100, tickUpper: 100, liquidityDelta: 100e18, salt: 0}),
      ZERO_BYTES
    );
    modifyLiquidityRouter.modifyLiquidity(
      pool10000,
      ModifyLiquidityParams({tickLower: -200, tickUpper: 200, liquidityDelta: 100e18, salt: 0}),
      ZERO_BYTES
    );
  }

  // ============ End-to-End: Set Fee -> Swap -> Accrue -> Collect ============

  function test_e2e_setFee_swap_collect() public {
    // Configure baseline curve
    CurveBreakpoint[] memory curve = new CurveBreakpoint[](3);
    curve[0] = CurveBreakpoint({lpFeeFloor: 0, protocolFee: PROTO_FEE_100});
    curve[1] = CurveBreakpoint({lpFeeFloor: 1000, protocolFee: PROTO_FEE_200});
    curve[2] = CurveBreakpoint({lpFeeFloor: 5000, protocolFee: PROTO_FEE_500});
    vm.prank(feeSetter);
    policy.setBaselineCurve(curve);

    // Trigger fee update on the 3000 bps pool
    adapter.triggerFeeUpdate(pool3000);
    vm.snapshotGasLastCall("fork: triggerFeeUpdate single pool");

    // Verify protocol fee was set on the PoolManager
    (,, uint24 protocolFee,) = manager.getSlot0(pool3000.toId());
    assertEq(protocolFee, PROTO_FEE_200);

    // Execute a swap (oneForZero, exact input)
    int256 swapAmount = -1e18;
    SwapParams memory params = SwapParams({
      zeroForOne: false, amountSpecified: swapAmount, sqrtPriceLimitX96: MAX_PRICE_LIMIT
    });
    BalanceDelta delta =
      swapRouter.swap(pool3000, params, PoolSwapTest.TestSettings(false, false), ZERO_BYTES);

    // Protocol fees should have accrued on currency1 (the input)
    uint256 expectedFee =
      uint256(uint128(-delta.amount1())) * 200 / ProtocolFeeLibrary.PIPS_DENOMINATOR;
    uint256 accrued = manager.protocolFeesAccrued(currency1);
    assertEq(accrued, expectedFee);
    assertTrue(accrued > 0, "No fees accrued");

    // Collect to TokenJar
    IV4FeeAdapter.CollectParams[] memory collectParams = new IV4FeeAdapter.CollectParams[](1);
    collectParams[0] = IV4FeeAdapter.CollectParams({currency: currency1, amount: 0});
    adapter.collect(collectParams);
    vm.snapshotGasLastCall("fork: collect single currency");

    // Verify fees landed in TokenJar
    assertEq(MockERC20(Currency.unwrap(currency1)).balanceOf(tokenJar), accrued);

    // Verify accrued is now 0
    assertEq(manager.protocolFeesAccrued(currency1), 0);
  }

  // ============ Baseline Curve: Different Tiers Get Different Fees ============

  function test_baselineCurve_differentPoolsDifferentFees() public {
    CurveBreakpoint[] memory curve = new CurveBreakpoint[](3);
    curve[0] = CurveBreakpoint({lpFeeFloor: 0, protocolFee: PROTO_FEE_100});
    curve[1] = CurveBreakpoint({lpFeeFloor: 1000, protocolFee: PROTO_FEE_300});
    curve[2] = CurveBreakpoint({lpFeeFloor: 5000, protocolFee: PROTO_FEE_500});
    vm.prank(feeSetter);
    policy.setBaselineCurve(curve);

    // Trigger all pools
    PoolKey[] memory keys = new PoolKey[](3);
    keys[0] = pool500;
    keys[1] = pool3000;
    keys[2] = pool10000;
    adapter.batchTriggerFeeUpdate(keys);
    vm.snapshotGasLastCall("fork: batchTriggerFeeUpdate 3 pools");

    // 500 bps pool -> floor 0 matches -> PROTO_FEE_100
    (,, uint24 fee500,) = manager.getSlot0(pool500.toId());
    assertEq(fee500, PROTO_FEE_100);

    // 3000 bps pool -> floor 1000 matches -> PROTO_FEE_300
    (,, uint24 fee3000,) = manager.getSlot0(pool3000.toId());
    assertEq(fee3000, PROTO_FEE_300);

    // 10000 bps pool -> floor 5000 matches -> PROTO_FEE_500
    (,, uint24 fee10000,) = manager.getSlot0(pool10000.toId());
    assertEq(fee10000, PROTO_FEE_500);
  }

  // ============ Pool Override Bypasses Policy ============

  function test_poolOverride_bypassesBaselineCurve() public {
    // Set baseline curve
    CurveBreakpoint[] memory curve = new CurveBreakpoint[](1);
    curve[0] = CurveBreakpoint({lpFeeFloor: 0, protocolFee: PROTO_FEE_100});
    vm.startPrank(feeSetter);
    policy.setBaselineCurve(curve);

    // Override one pool to PROTO_FEE_500
    adapter.setPoolOverride(pool3000.toId(), PROTO_FEE_500);
    vm.stopPrank();

    // Trigger both
    adapter.triggerFeeUpdate(pool3000);
    adapter.triggerFeeUpdate(pool500);

    // pool3000 gets the override
    (,, uint24 fee3000,) = manager.getSlot0(pool3000.toId());
    assertEq(fee3000, PROTO_FEE_500);

    // pool500 gets the baseline
    (,, uint24 fee500,) = manager.getSlot0(pool500.toId());
    assertEq(fee500, PROTO_FEE_100);
  }

  // ============ Pair Fee Overrides Curve ============

  function test_pairFee_overridesBaselineCurve() public {
    CurveBreakpoint[] memory curve = new CurveBreakpoint[](1);
    curve[0] = CurveBreakpoint({lpFeeFloor: 0, protocolFee: PROTO_FEE_100});
    vm.startPrank(feeSetter);
    policy.setBaselineCurve(curve);
    policy.setPairFee(currency0, currency1, PROTO_FEE_300);
    vm.stopPrank();

    adapter.triggerFeeUpdate(pool3000);

    // Pair fee takes precedence over baseline
    (,, uint24 fee,) = manager.getSlot0(pool3000.toId());
    assertEq(fee, PROTO_FEE_300);
  }

  // ============ Fees Accrue From Multiple Swaps ============

  function test_feesAccrueFromMultipleSwaps() public {
    CurveBreakpoint[] memory curve = new CurveBreakpoint[](1);
    curve[0] = CurveBreakpoint({lpFeeFloor: 0, protocolFee: PROTO_FEE_300});
    vm.prank(feeSetter);
    policy.setBaselineCurve(curve);

    adapter.triggerFeeUpdate(pool3000);

    // Execute 3 swaps in both directions
    for (uint256 i; i < 3; ++i) {
      swap(pool3000, true, -0.1e18, ZERO_BYTES);
      swap(pool3000, false, -0.1e18, ZERO_BYTES);
    }

    // Both currencies should have accrued fees
    uint256 accrued0 = manager.protocolFeesAccrued(currency0);
    uint256 accrued1 = manager.protocolFeesAccrued(currency1);
    assertTrue(accrued0 > 0, "No fees accrued on currency0");
    assertTrue(accrued1 > 0, "No fees accrued on currency1");

    // Collect both
    IV4FeeAdapter.CollectParams[] memory params = new IV4FeeAdapter.CollectParams[](2);
    params[0] = IV4FeeAdapter.CollectParams({currency: currency0, amount: 0});
    params[1] = IV4FeeAdapter.CollectParams({currency: currency1, amount: 0});
    adapter.collect(params);
    vm.snapshotGasLastCall("fork: collect 2 currencies");

    assertEq(MockERC20(Currency.unwrap(currency0)).balanceOf(tokenJar), accrued0);
    assertEq(MockERC20(Currency.unwrap(currency1)).balanceOf(tokenJar), accrued1);
  }

  // ============ Fee Update After Curve Change ============

  function test_curveChange_requiresRetrigger() public {
    // Set initial curve
    CurveBreakpoint[] memory curve = new CurveBreakpoint[](1);
    curve[0] = CurveBreakpoint({lpFeeFloor: 0, protocolFee: PROTO_FEE_100});
    vm.prank(feeSetter);
    policy.setBaselineCurve(curve);
    adapter.triggerFeeUpdate(pool3000);

    (,, uint24 feeBefore,) = manager.getSlot0(pool3000.toId());
    assertEq(feeBefore, PROTO_FEE_100);

    // Change curve
    curve[0] = CurveBreakpoint({lpFeeFloor: 0, protocolFee: PROTO_FEE_500});
    vm.prank(feeSetter);
    policy.setBaselineCurve(curve);

    // Pool still has old fee until retriggered
    (,, uint24 feeStale,) = manager.getSlot0(pool3000.toId());
    assertEq(feeStale, PROTO_FEE_100);

    // Retrigger picks up new curve
    adapter.triggerFeeUpdate(pool3000);
    (,, uint24 feeAfter,) = manager.getSlot0(pool3000.toId());
    assertEq(feeAfter, PROTO_FEE_500);
  }

  // ============ Policy Swap ============

  function test_policySwap_newPolicyTakesEffect() public {
    // Set up initial policy with fees
    CurveBreakpoint[] memory curve = new CurveBreakpoint[](1);
    curve[0] = CurveBreakpoint({lpFeeFloor: 0, protocolFee: PROTO_FEE_300});
    vm.prank(feeSetter);
    policy.setBaselineCurve(curve);
    adapter.triggerFeeUpdate(pool3000);

    (,, uint24 feeBefore,) = manager.getSlot0(pool3000.toId());
    assertEq(feeBefore, PROTO_FEE_300);

    // Deploy new policy with no curve (everything returns 0)
    V4FeePolicy newPolicy = new V4FeePolicy(manager);
    adapter.setPolicy(newPolicy);

    // Retrigger
    adapter.triggerFeeUpdate(pool3000);
    (,, uint24 feeAfter,) = manager.getSlot0(pool3000.toId());
    assertEq(feeAfter, 0);
  }

  // ============ Explicit Zero Override Prevents Fee Accrual ============

  function test_explicitZeroOverride_preventsFeeAccrual() public {
    // Set baseline curve with real fees
    CurveBreakpoint[] memory curve = new CurveBreakpoint[](1);
    curve[0] = CurveBreakpoint({lpFeeFloor: 0, protocolFee: PROTO_FEE_300});
    vm.startPrank(feeSetter);
    policy.setBaselineCurve(curve);

    // Override pool to explicit zero
    adapter.setPoolOverride(pool3000.toId(), 0);
    vm.stopPrank();

    adapter.triggerFeeUpdate(pool3000);

    // Pool should have zero protocol fee
    (,, uint24 fee,) = manager.getSlot0(pool3000.toId());
    assertEq(fee, 0);

    // Swap should not accrue any protocol fees
    swap(pool3000, true, -1e18, ZERO_BYTES);
    assertEq(manager.protocolFeesAccrued(currency0), 0);
    assertEq(manager.protocolFeesAccrued(currency1), 0);
  }

  // ============ Clear Override Restores Policy Behavior ============

  function test_clearOverride_restoresPolicy() public {
    CurveBreakpoint[] memory curve = new CurveBreakpoint[](1);
    curve[0] = CurveBreakpoint({lpFeeFloor: 0, protocolFee: PROTO_FEE_300});
    vm.startPrank(feeSetter);
    policy.setBaselineCurve(curve);
    adapter.setPoolOverride(pool3000.toId(), 0); // explicit zero
    vm.stopPrank();

    adapter.triggerFeeUpdate(pool3000);
    (,, uint24 feeZero,) = manager.getSlot0(pool3000.toId());
    assertEq(feeZero, 0);

    // Clear override
    vm.prank(feeSetter);
    adapter.clearPoolOverride(pool3000.toId());

    adapter.triggerFeeUpdate(pool3000);
    (,, uint24 feeRestored,) = manager.getSlot0(pool3000.toId());
    assertEq(feeRestored, PROTO_FEE_300);

    // Swap now accrues fees
    swap(pool3000, false, -1e18, ZERO_BYTES);
    assertTrue(manager.protocolFeesAccrued(currency1) > 0, "Fees should accrue after clear");
  }

  // ============ Partial Collection ============

  function test_partialCollection() public {
    CurveBreakpoint[] memory curve = new CurveBreakpoint[](1);
    curve[0] = CurveBreakpoint({lpFeeFloor: 0, protocolFee: PROTO_FEE_300});
    vm.prank(feeSetter);
    policy.setBaselineCurve(curve);
    adapter.triggerFeeUpdate(pool3000);

    // Swap to accrue fees
    swap(pool3000, false, -10e18, ZERO_BYTES);
    uint256 totalAccrued = manager.protocolFeesAccrued(currency1);
    assertTrue(totalAccrued > 0);

    // Collect only half
    uint256 halfAmount = totalAccrued / 2;
    IV4FeeAdapter.CollectParams[] memory params = new IV4FeeAdapter.CollectParams[](1);
    params[0] = IV4FeeAdapter.CollectParams({currency: currency1, amount: halfAmount});
    adapter.collect(params);

    // Half still accrued, half in TokenJar
    assertEq(manager.protocolFeesAccrued(currency1), totalAccrued - halfAmount);
    assertEq(MockERC20(Currency.unwrap(currency1)).balanceOf(tokenJar), halfAmount);
  }

  // ============ Asymmetric Fees ============

  function test_asymmetricFees() public {
    // 500 pips 0->1, 100 pips 1->0
    uint24 asymmetric = (100 << 12) | 500;
    vm.prank(feeSetter);
    adapter.setPoolOverride(pool3000.toId(), asymmetric);
    adapter.triggerFeeUpdate(pool3000);

    (,, uint24 fee,) = manager.getSlot0(pool3000.toId());
    assertEq(fee, asymmetric);

    // Swap zeroForOne (input is currency0, protocol fee = 500 pips on 0->1)
    swap(pool3000, true, -1e18, ZERO_BYTES);
    uint256 accrued0 = manager.protocolFeesAccrued(currency0);

    // Swap oneForZero (input is currency1, protocol fee = 100 pips on 1->0)
    swap(pool3000, false, -1e18, ZERO_BYTES);
    uint256 accrued1 = manager.protocolFeesAccrued(currency1);

    // Both should have fees, and currency0 should have more (higher fee direction)
    assertTrue(accrued0 > 0, "0->1 fees should accrue");
    assertTrue(accrued1 > 0, "1->0 fees should accrue");
    assertTrue(accrued0 > accrued1, "0->1 fee should be higher");
  }
}
