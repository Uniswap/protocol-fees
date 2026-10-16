// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Deployers} from "../lib/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {V4FeeAdapter, IV4FeeAdapter} from "../src/feeAdapters/V4FeeAdapter.sol";
import {V4FeePolicy} from "../src/feeAdapters/V4FeePolicy.sol";
import {V4StaticCurveRuleset} from "../src/feeAdapters/examples/V4StaticCurveRuleset.sol";
import {FeeBucket} from "../src/interfaces/IV4StaticCurveRuleset.sol";
import {MockProtocolFeeRuleset, MockSelfReportingHook} from "./mocks/MockProtocolFeeRuleset.sol";

/// @notice Integration tests on a real v4 PoolManager, which Deployers deploys locally. The tests
/// examine protocol fee accrual from real swaps, collection to the TokenJar, and the full fee
/// waterfall of the adapter, the policy, and the static curve.
contract V4FeeAdapterForkTest is Deployers {
  using PoolIdLibrary for PoolKey;
  using StateLibrary for IPoolManager;

  V4FeeAdapter adapter;
  V4FeePolicy policy;
  V4StaticCurveRuleset curve;
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

    // Deploy the adapter, the policy, and the static curve.
    policy = new V4FeePolicy(owner, feeSetter);
    curve = new V4StaticCurveRuleset(owner, feeSetter);
    adapter = new V4FeeAdapter(manager, tokenJar);
    adapter.setPolicy(policy);
    adapter.setFeeSetter(feeSetter);

    // Register the adapter as the protocolFeeController on the real PoolManager
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

  /// @dev Sets one bucket with a floor of 0 and `betaPips` = X. Thus, the static curve gives
  /// `protocolFee = X * lpFee / 1_000_000`.
  function _setSingleBucketSlope(uint32 betaPips) internal {
    FeeBucket[] memory buckets = new FeeBucket[](1);
    buckets[0] = FeeBucket({lpFeeFloor: 0, alphaPips: 0, betaPips: betaPips});
    vm.prank(feeSetter);
    curve.setFeeBuckets(buckets);
  }

  /// @dev Sets the static curve as the ruleset of all pools that have no hook.
  function _registerCurveForHooklessPools() internal {
    address hooklessSentinel = policy.HOOKLESS_POLICY_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(hooklessSentinel, curve);
  }

  // ============ Static curve on hooked pools ============

  function test_fork_staticHook_staticCurve_triggersCurveFeeOnManager() public {
    // This hook has only the beforeSwap flag. Thus, it does not do custom accounting.
    IHooks hook = IHooks(address(uint160(1 << 7)));
    PoolKey memory staticHookPool;
    (staticHookPool,) = initPool(currency0, currency1, hook, 3000, 60, SQRT_PRICE_1_1);

    // 100_000 pips × 3000 / 1_000_000 = 300 in each direction (= PROTO_FEE_300)
    _setSingleBucketSlope(100_000);
    address staticCurveSentinel = policy.STATIC_CURVE_POLICY_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(staticCurveSentinel, curve);

    adapter.triggerFeeUpdate(staticHookPool);

    (,, uint24 fee,) = manager.getSlot0(staticHookPool.toId());
    assertEq(fee, PROTO_FEE_300);
  }

  function test_fork_staticHook_registeredRuleset_beatsStaticCurve() public {
    // This hook has only the beforeSwap flag. Thus, it does not do custom accounting.
    IHooks hook = IHooks(address(uint160(1 << 7)));
    PoolKey memory staticHookPool;
    (staticHookPool,) = initPool(currency0, currency1, hook, 3000, 60, SQRT_PRICE_1_1);

    // The static curve gives PROTO_FEE_300 for this pool.
    _setSingleBucketSlope(100_000);
    address staticCurveSentinel = policy.STATIC_CURVE_POLICY_SENTINEL();
    MockProtocolFeeRuleset ruleset =
      new MockProtocolFeeRuleset({fee: PROTO_FEE_200, reverts: false});
    vm.startPrank(feeSetter);
    policy.setProtocolFeeRuleset(staticCurveSentinel, curve);
    policy.setProtocolFeeRuleset(address(hook), ruleset);
    vm.stopPrank();

    adapter.triggerFeeUpdate(staticHookPool);

    (,, uint24 fee,) = manager.getSlot0(staticHookPool.toId());
    assertEq(fee, PROTO_FEE_200);
  }

  // ============ Hook fee on a dynamic-fee pool ============

  function test_fork_selfReportingHook_dynamicFeePool_accruesHookFee() public {
    // A hook address without permission flags is correct for a dynamic-fee pool. The PoolManager
    // does not call this hook.
    address hook = address(uint160(1) << 100);
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: PROTO_FEE_200, reverts: false, supportsERC165: true, supportsRuleset: true
    });
    vm.etch(hook, address(implementation).code);

    PoolKey memory dynamicPool;
    (dynamicPool,) = initPool(
      currency0, currency1, IHooks(hook), LPFeeLibrary.DYNAMIC_FEE_FLAG, 60, SQRT_PRICE_1_1
    );
    modifyLiquidityRouter.modifyLiquidity(
      dynamicPool,
      ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100e18, salt: 0}),
      ZERO_BYTES
    );
    // A dynamic-fee pool starts with an LP fee of zero. Only the hook can change the LP fee.
    vm.prank(hook);
    manager.updateDynamicLPFee(dynamicPool, 3000);

    adapter.triggerFeeUpdate(dynamicPool);
    (,, uint24 protocolFee,) = manager.getSlot0(dynamicPool.toId());
    assertEq(protocolFee, PROTO_FEE_200);

    // Swap oneForZero (the input is currency1). The protocol fee is 200 pips of the input.
    SwapParams memory params =
      SwapParams({zeroForOne: false, amountSpecified: -1e18, sqrtPriceLimitX96: MAX_PRICE_LIMIT});
    BalanceDelta delta =
      swapRouter.swap(dynamicPool, params, PoolSwapTest.TestSettings(false, false), ZERO_BYTES);

    uint256 expectedFee =
      uint256(uint128(-delta.amount1())) * 200 / ProtocolFeeLibrary.PIPS_DENOMINATOR;
    assertEq(manager.protocolFeesAccrued(currency1), expectedFee);
  }

  // ============ Ruleset that reverts ============

  function test_fork_revertingRuleset_revertsBatch_untilPoolOverride() public {
    // 100_000 pips × pool3000.fee (3000) / 1_000_000 = 300 in each direction (= PROTO_FEE_300)
    _setSingleBucketSlope(100_000);
    _registerCurveForHooklessPools();

    // This hook has only the beforeSwap flag. Thus, it does not do custom accounting.
    IHooks hook = IHooks(address(uint160(1 << 7)));
    PoolKey memory brokenPool;
    (brokenPool,) = initPool(currency0, currency1, hook, 3000, 60, SQRT_PRICE_1_1);
    MockProtocolFeeRuleset reverting = new MockProtocolFeeRuleset({fee: 0, reverts: true});
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(address(hook), reverting);

    PoolKey[] memory keys = new PoolKey[](2);
    keys[0] = pool3000;
    keys[1] = brokenPool;

    // The ruleset reverts. Thus, the full batch reverts, and pool3000 does not get a fee update.
    vm.expectRevert(MockProtocolFeeRuleset.MockReverted.selector);
    adapter.batchTriggerFeeUpdate(keys);

    // With a pool override, the adapter does not call the policy for that pool.
    vm.prank(feeSetter);
    adapter.setPoolOverride(brokenPool.toId(), PROTO_FEE_100);
    adapter.batchTriggerFeeUpdate(keys);

    (,, uint24 healthyFee,) = manager.getSlot0(pool3000.toId());
    (,, uint24 overriddenFee,) = manager.getSlot0(brokenPool.toId());
    assertEq(healthyFee, PROTO_FEE_300);
    assertEq(overriddenFee, PROTO_FEE_100);
  }

  // ============ End-to-End: Set Fee -> Swap -> Accrue -> Collect ============

  function test_e2e_setFee_swap_collect() public {
    // 66_667 pips × pool3000.fee (3000) / 1_000_000 = 200 per direction (= PROTO_FEE_200)
    _setSingleBucketSlope(66_667);
    _registerCurveForHooklessPools();

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

  // ============ Static Curve: The Fee Is Linear In The LP Fee ============

  function test_buckets_differentPoolsLinearlyScaled() public {
    // slope = 100_000 (10% of LP fee)
    //   pool500   (LP 500)    -> 50  per direction
    //   pool3000  (LP 3000)   -> 300 per direction (= PROTO_FEE_300)
    //   pool10000 (LP 10_000) -> 1000 per direction, clamped to MAX_PROTOCOL_FEE
    _setSingleBucketSlope(100_000);
    _registerCurveForHooklessPools();

    PoolKey[] memory keys = new PoolKey[](3);
    keys[0] = pool500;
    keys[1] = pool3000;
    keys[2] = pool10000;
    adapter.batchTriggerFeeUpdate(keys);
    vm.snapshotGasLastCall("fork: batchTriggerFeeUpdate 3 pools");

    uint24 expected50 = (50 << 12) | 50;
    (,, uint24 fee500,) = manager.getSlot0(pool500.toId());
    assertEq(fee500, expected50);

    (,, uint24 fee3000,) = manager.getSlot0(pool3000.toId());
    assertEq(fee3000, PROTO_FEE_300);

    uint24 expected1000 = (1000 << 12) | 1000;
    (,, uint24 fee10000,) = manager.getSlot0(pool10000.toId());
    assertEq(fee10000, expected1000);
  }

  // ============ Pool Override Bypasses Policy ============

  function test_poolOverride_bypassesPolicy() public {
    // 200_000 pips × pool500.fee (500) / 1_000_000 = 100 per direction (= PROTO_FEE_100)
    _setSingleBucketSlope(200_000);
    _registerCurveForHooklessPools();

    // Override one pool to PROTO_FEE_500
    vm.prank(feeSetter);
    adapter.setPoolOverride(pool3000.toId(), PROTO_FEE_500);

    // Trigger both
    adapter.triggerFeeUpdate(pool3000);
    adapter.triggerFeeUpdate(pool500);

    // pool3000 gets the override. The static curve gives a higher fee.
    (,, uint24 fee3000,) = manager.getSlot0(pool3000.toId());
    assertEq(fee3000, PROTO_FEE_500);

    // pool500 gets the fee from the static curve.
    (,, uint24 fee500,) = manager.getSlot0(pool500.toId());
    assertEq(fee500, PROTO_FEE_100);
  }

  // ============ Fees Accrue From Multiple Swaps ============

  function test_feesAccrueFromMultipleSwaps() public {
    // 100_000 pips × pool3000.fee (3000) / 1_000_000 = 300 per direction (= PROTO_FEE_300)
    _setSingleBucketSlope(100_000);
    _registerCurveForHooklessPools();

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

  // ============ Fee Update After Bucket Change ============

  function test_bucketsChange_requiresRetrigger() public {
    // 33_334 pips × 3000 / 1_000_000 = 100 per direction (= PROTO_FEE_100, integer-truncated)
    _setSingleBucketSlope(33_334);
    _registerCurveForHooklessPools();
    adapter.triggerFeeUpdate(pool3000);

    (,, uint24 feeBefore,) = manager.getSlot0(pool3000.toId());
    assertEq(feeBefore, PROTO_FEE_100);

    // 166_667 pips × 3000 / 1_000_000 = 500 per direction (= PROTO_FEE_500, integer-truncated)
    _setSingleBucketSlope(166_667);

    // Pool still has old fee until retriggered
    (,, uint24 feeStale,) = manager.getSlot0(pool3000.toId());
    assertEq(feeStale, PROTO_FEE_100);

    // The next trigger uses the new buckets.
    adapter.triggerFeeUpdate(pool3000);
    (,, uint24 feeAfter,) = manager.getSlot0(pool3000.toId());
    assertEq(feeAfter, PROTO_FEE_500);
  }

  // ============ Policy Swap ============

  function test_policySwap_newPolicyTakesEffect() public {
    // 100_000 pips × pool3000.fee (3000) / 1_000_000 = 300 per direction (= PROTO_FEE_300)
    _setSingleBucketSlope(100_000);
    _registerCurveForHooklessPools();
    adapter.triggerFeeUpdate(pool3000);

    (,, uint24 feeBefore,) = manager.getSlot0(pool3000.toId());
    assertEq(feeBefore, PROTO_FEE_300);

    // Deploy a new policy without rulesets and without a default fee. It returns 0 for all pools.
    V4FeePolicy newPolicy = new V4FeePolicy(owner, feeSetter);
    adapter.setPolicy(newPolicy);

    // Retrigger
    adapter.triggerFeeUpdate(pool3000);
    (,, uint24 feeAfter,) = manager.getSlot0(pool3000.toId());
    assertEq(feeAfter, 0);
  }

  // ============ Explicit Zero Override Prevents Fee Accrual ============

  function test_explicitZeroOverride_preventsFeeAccrual() public {
    // 100_000 pips × pool3000.fee (3000) / 1_000_000 = 300 per direction (= PROTO_FEE_300)
    _setSingleBucketSlope(100_000);
    _registerCurveForHooklessPools();

    // Override pool to explicit zero
    vm.prank(feeSetter);
    adapter.setPoolOverride(pool3000.toId(), 0);

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
    // 100_000 pips × pool3000.fee (3000) / 1_000_000 = 300 per direction (= PROTO_FEE_300)
    _setSingleBucketSlope(100_000);
    _registerCurveForHooklessPools();
    vm.prank(feeSetter);
    adapter.setPoolOverride(pool3000.toId(), 0); // explicit zero

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
    // 100_000 pips × pool3000.fee (3000) / 1_000_000 = 300 per direction (= PROTO_FEE_300)
    _setSingleBucketSlope(100_000);
    _registerCurveForHooklessPools();
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
