// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Deployers} from "../lib/v4-core/test/utils/Deployers.sol";
import {BaseTestHooks} from "../lib/v4-core/src/test/BaseTestHooks.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {V4FeeAdapter, IV4FeeAdapter} from "../src/feeAdapters/V4FeeAdapter.sol";
import {V4FeePolicy, IV4FeePolicy} from "../src/feeAdapters/V4FeePolicy.sol";
import {FeeBucket} from "../src/interfaces/IV4FeePolicy.sol";

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

  // Manager-side packed (12+12) — what shows up in Slot0 after the adapter clamps and
  // pushes. Used for assertions on `manager.getSlot0(...).protocolFee`.
  uint24 constant PROTO_FEE_100 = (uint24(100) << 12) | 100;
  uint24 constant PROTO_FEE_200 = (uint24(200) << 12) | 200;
  uint24 constant PROTO_FEE_300 = (uint24(300) << 12) | 300;
  uint24 constant PROTO_FEE_500 = (uint24(500) << 12) | 500;

  // Raw uint48 packed (24+24) — the internal storage representation. Used wherever we
  // call `setPoolOverride` / `setPairFee` and have to pass the wider type.
  uint48 constant RAW_FEE_100 = (uint48(100) << 24) | 100;
  uint48 constant RAW_FEE_200 = (uint48(200) << 24) | 200;
  uint48 constant RAW_FEE_300 = (uint48(300) << 24) | 300;
  uint48 constant RAW_FEE_500 = (uint48(500) << 24) | 500;

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

  /// @dev Equivalent of the pre-bucket-era global multiplier: a single bucket starting
  /// at floor 0 with `betaPips = X`. Result: `protocolFee = X * lpFee / 1_000_000`.
  function _singleBucketSlope(uint32 betaPips) internal pure returns (FeeBucket[] memory bs) {
    bs = new FeeBucket[](1);
    bs[0] = FeeBucket({lpFeeFloor: 0, alphaPips: 0, betaPips: betaPips});
  }

  // ============ End-to-End: Set Fee -> Swap -> Accrue -> Collect ============

  function test_e2e_setFee_swap_collect() public {
    // 66_667 pips × pool3000.fee (3000) / 1_000_000 = 200 per direction (= PROTO_FEE_200)
    vm.prank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(66_667));

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

  // ============ Multiplier: Pools Scale Linearly With LP Fee ============

  function test_buckets_differentPoolsLinearlyScaled() public {
    // multiplier = 100_000 (10% of LP fee)
    //   pool500   (LP 500)    -> 50  per direction
    //   pool3000  (LP 3000)   -> 300 per direction (= PROTO_FEE_300)
    //   pool10000 (LP 10_000) -> 1000 per direction, clamped to MAX_PROTOCOL_FEE
    vm.prank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(100_000));

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
    vm.startPrank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(200_000));

    // Override one pool to PROTO_FEE_500 (pass the raw uint48 representation)
    adapter.setPoolOverride(pool3000.toId(), RAW_FEE_500);
    vm.stopPrank();

    // Trigger both
    adapter.triggerFeeUpdate(pool3000);
    adapter.triggerFeeUpdate(pool500);

    // pool3000 gets the override (multiplier-derived value would have been higher)
    (,, uint24 fee3000,) = manager.getSlot0(pool3000.toId());
    assertEq(fee3000, PROTO_FEE_500);

    // pool500 gets the multiplier-derived fee
    (,, uint24 fee500,) = manager.getSlot0(pool500.toId());
    assertEq(fee500, PROTO_FEE_100);
  }

  // ============ Pair Fee Overrides Multiplier ============

  function test_pairFee_overridesMultiplier() public {
    vm.startPrank(feeSetter);
    // Any non-zero multiplier — pair fee should win regardless
    policy.setFeeBuckets(_singleBucketSlope(100_000));
    policy.setPairFee(currency0, currency1, RAW_FEE_300);
    vm.stopPrank();

    adapter.triggerFeeUpdate(pool3000);

    // Pair fee takes precedence over the multiplier
    (,, uint24 fee,) = manager.getSlot0(pool3000.toId());
    assertEq(fee, PROTO_FEE_300);
  }

  // ============ Fees Accrue From Multiple Swaps ============

  function test_feesAccrueFromMultipleSwaps() public {
    // 100_000 pips × pool3000.fee (3000) / 1_000_000 = 300 per direction (= PROTO_FEE_300)
    vm.prank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(100_000));

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

  // ============ Fee Update After Multiplier Change ============

  function test_bucketsChange_requiresRetrigger() public {
    // 33_334 pips × 3000 / 1_000_000 = 100 per direction (= PROTO_FEE_100, integer-truncated)
    vm.prank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(33_334));
    adapter.triggerFeeUpdate(pool3000);

    (,, uint24 feeBefore,) = manager.getSlot0(pool3000.toId());
    assertEq(feeBefore, PROTO_FEE_100);

    // 166_667 pips × 3000 / 1_000_000 = 500 per direction (= PROTO_FEE_500, integer-truncated)
    vm.prank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(166_667));

    // Pool still has old fee until retriggered
    (,, uint24 feeStale,) = manager.getSlot0(pool3000.toId());
    assertEq(feeStale, PROTO_FEE_100);

    // Retrigger picks up new multiplier
    adapter.triggerFeeUpdate(pool3000);
    (,, uint24 feeAfter,) = manager.getSlot0(pool3000.toId());
    assertEq(feeAfter, PROTO_FEE_500);
  }

  // ============ Policy Swap ============

  function test_policySwap_newPolicyTakesEffect() public {
    // 100_000 pips × pool3000.fee (3000) / 1_000_000 = 300 per direction (= PROTO_FEE_300)
    vm.prank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(100_000));
    adapter.triggerFeeUpdate(pool3000);

    (,, uint24 feeBefore,) = manager.getSlot0(pool3000.toId());
    assertEq(feeBefore, PROTO_FEE_300);

    // Deploy new policy with no multiplier configured (default 0, everything returns 0)
    V4FeePolicy newPolicy = new V4FeePolicy(manager);
    adapter.setPolicy(newPolicy);

    // Retrigger
    adapter.triggerFeeUpdate(pool3000);
    (,, uint24 feeAfter,) = manager.getSlot0(pool3000.toId());
    assertEq(feeAfter, 0);
  }

  // ============ Explicit Zero Override Prevents Fee Accrual ============

  function test_explicitZeroOverride_preventsFeeAccrual() public {
    // 100_000 pips × pool3000.fee (3000) / 1_000_000 = 300 per direction (= PROTO_FEE_300)
    vm.startPrank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(100_000));

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
    // 100_000 pips × pool3000.fee (3000) / 1_000_000 = 300 per direction (= PROTO_FEE_300)
    vm.startPrank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(100_000));
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
    // 100_000 pips × pool3000.fee (3000) / 1_000_000 = 300 per direction (= PROTO_FEE_300)
    vm.prank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(100_000));
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
    // 500 pips 0->1, 100 pips 1->0. Set via uint48 (24+24) but Slot0 stores uint24
    // (12+12). Both halves are below MAX_PROTOCOL_FEE so the round-trip is lossless.
    uint48 asymmetric = (uint48(100) << 24) | 500;
    uint24 asymmetricMgr = (uint24(100) << 12) | 500;
    vm.prank(feeSetter);
    adapter.setPoolOverride(pool3000.toId(), asymmetric);
    adapter.triggerFeeUpdate(pool3000);

    (,, uint24 fee,) = manager.getSlot0(pool3000.toId());
    assertEq(fee, asymmetricMgr);

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

  // ============ Custom-Accounting Hook: Uncapped Direct-Read Fee Path ============
  //
  // These tests verify the manager-push short-circuit + uncapped direct-read view
  // work end-to-end against a real PoolManager:
  //  - For a pool whose hook address has any RETURNS_DELTA bit set, `triggerFeeUpdate`
  //    writes Slot0.protocolFee = 0 regardless of policy state, pair-fee setting, or
  //    pool override. The hook reads its uncapped fee directly from the adapter via
  //    `getFeeRaw` and charges via its own delta accounting.
  //  - `getFeeRaw` returns the raw uint48 (no MAX_PROTOCOL_FEE clamp), so fees well
  //    above 1000 pips (e.g. 50_000 = 5%) flow through unchanged.
  //
  // Non-custom-accounting contrast — Slot0 push and MAX_PROTOCOL_FEE clamp on the
  // standard path — is already covered by `test_buckets_differentPoolsLinearlyScaled`
  // (pool10000 with multiplier 100_000 → derived 1000 pips/dir = MAX_PROTOCOL_FEE),
  // so it's referenced here rather than duplicated.

  /// @dev Hook address with `BEFORE_SWAP_FLAG` (bit 7) and
  /// `BEFORE_SWAP_RETURNS_DELTA_FLAG` (bit 3) set. Bit 3 puts it in the custom-
  /// accounting mask (bits 0-3) so `_isCustomAccounting` returns true. Bit 7 is
  /// required by `Hooks.isValidHookAddress` since bit 3 implies a beforeSwap delta.
  address constant CUSTOM_ACCOUNTING_HOOK_ADDR =
    address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));

  /// @dev Packs a single per-direction value into a symmetric uint48
  /// `(v << 24) | v`. Used for configuring uncapped pair fees that exceed
  /// MAX_PROTOCOL_FEE.
  function _symmetric(uint24 v) internal pure returns (uint48) {
    return (uint48(v) << 24) | uint48(v);
  }

  /// @dev Etches a minimal `BaseTestHooks` runtime at `CUSTOM_ACCOUNTING_HOOK_ADDR`
  /// and initializes a pool with that hook. The hook is never invoked in these tests
  /// (no swaps), so the revert-all body is sufficient — bytecode only needs to exist
  /// to satisfy `Hooks.isValidHookAddress`. Returns the initialized pool key.
  function _initCustomAccountingPool() internal returns (PoolKey memory customKey) {
    address impl = address(new BaseTestHooks());
    vm.etch(CUSTOM_ACCOUNTING_HOOK_ADDR, impl.code);
    // Use a distinct tick spacing so the PoolKey is unique from `pool3000` etc.
    (customKey,) =
      initPool(currency0, currency1, IHooks(CUSTOM_ACCOUNTING_HOOK_ADDR), 3000, 60, SQRT_PRICE_1_1);
  }

  /// @dev Wires up the standard "uncapped Classified" setup: classify the hook into
  /// family 1, set that family's multiplier to 100% (1_000_000), and set a symmetric
  /// pair fee of `feePerDir` pips. `computeFee` returns `pairFee * multiplier / 1e6`
  /// per direction = `feePerDir` per direction.
  function _configureClassifiedFee(uint24 feePerDir) internal {
    vm.startPrank(feeSetter);
    policy.setHookFamily(CUSTOM_ACCOUNTING_HOOK_ADDR, 1);
    policy.setFamilyMultiplier(1, 1_000_000);
    policy.setPairFee(currency0, currency1, _symmetric(feePerDir));
    vm.stopPrank();
  }

  function test_customAccounting_getFeeRaw_uncapped() public {
    PoolKey memory customKey = _initCustomAccountingPool();

    // 50_000 pips = 5%, far exceeding MAX_PROTOCOL_FEE = 1000 pips. The raw view
    // must NOT clamp.
    assertGt(
      uint256(50_000),
      uint256(ProtocolFeeLibrary.MAX_PROTOCOL_FEE),
      "test fee must exceed MAX_PROTOCOL_FEE"
    );

    _configureClassifiedFee(50_000);

    // getFeeRaw is the direct-read for custom-accounting hooks; uint48 flows through
    // unclamped.
    assertEq(adapter.getFeeRaw(customKey), _symmetric(50_000));

    // getFee (manager-compat uint24 view) clamps each direction to MAX_PROTOCOL_FEE.
    uint24 expectedClamped = (uint24(1000) << 12) | 1000;
    assertEq(adapter.getFee(customKey), expectedClamped);
  }

  function test_customAccounting_triggerFeeUpdate_pushesZero() public {
    PoolKey memory customKey = _initCustomAccountingPool();

    _configureClassifiedFee(50_000);

    // Sanity: the manager-compat view clamps; only the short-circuit prevents this
    // clamped value from being pushed to Slot0.
    uint24 expectedClamped = (uint24(1000) << 12) | 1000;
    assertEq(adapter.getFee(customKey), expectedClamped);

    // Expect FeeUpdateTriggered(msg.sender, id, 0). Both indexed topics matter
    // (caller + poolId) and the data payload must be 0.
    vm.expectEmit(true, true, true, true, address(adapter));
    emit IV4FeeAdapter.FeeUpdateTriggered(address(this), customKey.toId(), 0);
    adapter.triggerFeeUpdate(customKey);

    (,, uint24 protocolFee,) = manager.getSlot0(customKey.toId());
    assertEq(protocolFee, 0, "custom-accounting Slot0.protocolFee must be zero");
  }

  function test_customAccounting_triggerFeeUpdate_stillZero_afterReConfigure() public {
    PoolKey memory customKey = _initCustomAccountingPool();

    _configureClassifiedFee(50_000);

    // First trigger: short-circuit pushes 0.
    adapter.triggerFeeUpdate(customKey);
    (,, uint24 fee1,) = manager.getSlot0(customKey.toId());
    assertEq(fee1, 0, "first trigger must push zero");
    assertEq(adapter.getFeeRaw(customKey), _symmetric(50_000));

    // Reconfigure to a different uncapped value. familyMultiplier stays at 100%, so
    // the new pair fee flows through unchanged.
    vm.prank(feeSetter);
    policy.setPairFee(currency0, currency1, _symmetric(100_000));
    assertEq(adapter.getFeeRaw(customKey), _symmetric(100_000));

    // Re-trigger: still zero. The two paths are independent — reconfiguring the
    // direct-read fee never affects Slot0.
    adapter.triggerFeeUpdate(customKey);
    (,, uint24 fee2,) = manager.getSlot0(customKey.toId());
    assertEq(fee2, 0, "re-trigger must still push zero");

    // Direct-read view stays consistent with the new configuration.
    assertEq(adapter.getFeeRaw(customKey), _symmetric(100_000));
  }

  function test_customAccounting_poolOverride_isIgnored() public {
    PoolKey memory customKey = _initCustomAccountingPool();
    PoolId id = customKey.toId();

    // Set a non-zero, uncapped pool override directly on the adapter. This bypasses
    // the policy entirely for both `getFeeRaw` and `getFee`.
    vm.prank(feeSetter);
    adapter.setPoolOverride(id, _symmetric(50_000));

    // Override flows through the raw view unclamped — this is the value the
    // custom-accounting hook reads at swap time.
    assertEq(adapter.getFeeRaw(customKey), _symmetric(50_000));

    // Manager-compat view clamps the override.
    uint24 expectedClamped = (uint24(1000) << 12) | 1000;
    assertEq(adapter.getFee(customKey), expectedClamped);

    // Triggering still pushes 0 — the short-circuit bypasses the pool override too,
    // since the manager-side fee is structurally unused for custom-accounting pools.
    adapter.triggerFeeUpdate(customKey);
    (,, uint24 protocolFee,) = manager.getSlot0(id);
    assertEq(protocolFee, 0, "pool override must be ignored for custom-accounting pools");
  }
}
