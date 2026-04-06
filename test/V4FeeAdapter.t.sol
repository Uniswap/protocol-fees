// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";

import {V4FeeAdapter, IV4FeeAdapter} from "../src/feeAdapters/V4FeeAdapter.sol";
import {V4FeePolicy, IV4FeePolicy} from "../src/feeAdapters/V4FeePolicy.sol";
import {CurveBreakpoint} from "../src/interfaces/IV4FeePolicy.sol";
import {MockV4PoolManager} from "./mocks/MockV4PoolManager.sol";
import {
  MockFeeClassifiedHook,
  GriefingHook,
  RevertingHook
} from "./mocks/MockFeeClassifiedHook.sol";

contract V4FeeAdapterTest is Test {
  using PoolIdLibrary for PoolKey;
  using CurrencyLibrary for Currency;

  MockV4PoolManager public poolManager;
  V4FeeAdapter public adapter;
  V4FeePolicy public policy;

  address public owner;
  address public feeSetter;
  address public tokenJar;
  address public alice;

  MockERC20 public token0;
  MockERC20 public token1;

  // Standard pool keys for testing
  PoolKey public standardKey; // static fee, no hook
  PoolKey public hookKey; // static fee, non-custom-accounting hook
  PoolKey public dynamicKey; // dynamic fee, no hook

  // Protocol fee constants (symmetric 0->1 and 1->0)
  uint24 constant FEE_100 = (100 << 12) | 100; // 100 pips both directions
  uint24 constant FEE_200 = (200 << 12) | 200;
  uint24 constant FEE_300 = (300 << 12) | 300;
  uint24 constant FEE_500 = (500 << 12) | 500;
  uint24 constant FEE_1000 = (1000 << 12) | 1000; // max both directions

  function setUp() public {
    owner = makeAddr("owner");
    feeSetter = makeAddr("feeSetter");
    tokenJar = makeAddr("tokenJar");
    alice = makeAddr("alice");

    // Deploy tokens (sorted by address)
    token0 = new MockERC20("Token0", "T0", 18);
    token1 = new MockERC20("Token1", "T1", 18);
    if (address(token0) > address(token1)) (token0, token1) = (token1, token0);

    // Deploy mock pool manager
    vm.prank(owner);
    poolManager = new MockV4PoolManager(owner);

    // Deploy policy and adapter
    vm.startPrank(owner);
    policy = new V4FeePolicy(IPoolManager(address(poolManager)));
    adapter = new V4FeeAdapter(IPoolManager(address(poolManager)), tokenJar);
    adapter.setPolicy(policy);
    adapter.setFeeSetter(feeSetter);
    policy.setFeeSetter(feeSetter);

    // Register adapter as protocolFeeController
    poolManager.setProtocolFeeController(address(adapter));
    vm.stopPrank();

    // Build standard pool keys
    standardKey = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(address(0))
    });

    // Hook at address with NO return-delta flags (bits 0-3 clear, bit 7 set = beforeSwap)
    hookKey = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(address(uint160(1 << 7))) // beforeSwap only, no custom accounting
    });

    dynamicKey = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
      tickSpacing: 60,
      hooks: IHooks(address(0))
    });

    // Initialize pools
    poolManager.mockInitialize(standardKey);
    poolManager.mockInitialize(hookKey);
    poolManager.mockInitialize(dynamicKey);
  }

  // ============ Helpers ============

  function _buildCurve() internal pure returns (CurveBreakpoint[] memory) {
    CurveBreakpoint[] memory curve = new CurveBreakpoint[](4);
    curve[0] = CurveBreakpoint({lpFeeFloor: 0, protocolFee: FEE_100});
    curve[1] = CurveBreakpoint({lpFeeFloor: 500, protocolFee: FEE_200});
    curve[2] = CurveBreakpoint({lpFeeFloor: 3000, protocolFee: FEE_300});
    curve[3] = CurveBreakpoint({lpFeeFloor: 10_000, protocolFee: FEE_500});
    return curve;
  }

  function _pairHash() internal view returns (bytes32) {
    return keccak256(
      abi.encodePacked(
        Currency.unwrap(standardKey.currency0), Currency.unwrap(standardKey.currency1)
      )
    );
  }

  /// @dev Deploy a mock hook at a specific address using CREATE2.
  /// The lowest 14 bits of the address encode hook permissions.
  function _deployHookAt(uint160 flags, uint8 selfReportFamily) internal returns (address) {
    // Deploy mock at an address with the desired flags via vm.etch
    address hookAddr = address(flags);
    MockFeeClassifiedHook impl = new MockFeeClassifiedHook(selfReportFamily);
    vm.etch(hookAddr, address(impl).code);
    // Overwrite the immutable familyId in the etched bytecode's storage
    vm.store(hookAddr, bytes32(0), bytes32(uint256(selfReportFamily)));
    return hookAddr;
  }

  // ============ Adapter: Construction ============

  function test_adapter_constructor() public view {
    assertEq(address(adapter.POOL_MANAGER()), address(poolManager));
    assertEq(adapter.TOKEN_JAR(), tokenJar);
    assertEq(address(adapter.policy()), address(policy));
    assertEq(adapter.feeSetter(), feeSetter);
  }

  // ============ Adapter: Admin ============

  function test_setPolicy_success() public {
    V4FeePolicy newPolicy = new V4FeePolicy(IPoolManager(address(poolManager)));
    vm.expectEmit(true, true, false, false, address(adapter));
    emit IV4FeeAdapter.PolicyUpdated(address(policy), address(newPolicy));
    vm.prank(owner);
    adapter.setPolicy(newPolicy);
    assertEq(address(adapter.policy()), address(newPolicy));
  }

  function test_setPolicy_revertsUnauthorized() public {
    vm.prank(alice);
    vm.expectRevert("UNAUTHORIZED");
    adapter.setPolicy(IV4FeePolicy(address(0)));
  }

  function test_setPolicy_zeroDisablesPolicy() public {
    vm.prank(owner);
    adapter.setPolicy(IV4FeePolicy(address(0)));
    assertEq(adapter.getFee(standardKey), 0);
  }

  function test_setFeeSetter_adapter() public {
    vm.expectEmit(true, true, false, false, address(adapter));
    emit IV4FeeAdapter.FeeSetterUpdated(feeSetter, alice);
    vm.prank(owner);
    adapter.setFeeSetter(alice);
    assertEq(adapter.feeSetter(), alice);
  }

  function test_setFeeSetter_adapter_revertsUnauthorized() public {
    vm.prank(alice);
    vm.expectRevert("UNAUTHORIZED");
    adapter.setFeeSetter(alice);
  }

  // ============ Adapter: Pool Overrides ============

  function test_setPoolOverride_success() public {
    PoolId id = standardKey.toId();
    vm.expectEmit(true, false, false, true, address(adapter));
    emit IV4FeeAdapter.PoolOverrideUpdated(id, FEE_500);
    vm.prank(feeSetter);
    adapter.setPoolOverride(id, FEE_500);
    vm.snapshotGasLastCall("adapter.setPoolOverride");
    assertEq(adapter.getFee(standardKey), FEE_500);
  }

  function test_setPoolOverride_zeroSetsExplicitZero() public {
    PoolId id = standardKey.toId();

    // Configure policy to return FEE_300
    vm.prank(feeSetter);
    policy.setBaselineCurve(_buildCurve());
    assertEq(adapter.getFee(standardKey), FEE_300);

    // Set pool override to explicit zero -should NOT fall through to policy
    vm.prank(feeSetter);
    adapter.setPoolOverride(id, 0);

    // Raw storage holds sentinel (explicit zero), getFee decodes to 0
    assertEq(adapter.poolOverrides(id), type(uint24).max);
    assertEq(adapter.getFee(standardKey), 0);
  }

  function test_clearPoolOverride_fallsThroughToPolicy() public {
    PoolId id = standardKey.toId();

    vm.prank(feeSetter);
    policy.setBaselineCurve(_buildCurve());

    // Set override then clear it
    vm.startPrank(feeSetter);
    adapter.setPoolOverride(id, FEE_500);
    assertEq(adapter.getFee(standardKey), FEE_500);

    adapter.clearPoolOverride(id);
    vm.stopPrank();

    // Raw storage is 0 (not set), falls through to policy
    assertEq(adapter.poolOverrides(id), 0);
    assertEq(adapter.getFee(standardKey), FEE_300);
  }

  function test_clearPoolOverride_revertsUnauthorized() public {
    vm.prank(alice);
    vm.expectRevert(IV4FeeAdapter.Unauthorized.selector);
    adapter.clearPoolOverride(standardKey.toId());
  }

  function test_setPoolOverride_revertsUnauthorized() public {
    vm.prank(alice);
    vm.expectRevert(IV4FeeAdapter.Unauthorized.selector);
    adapter.setPoolOverride(standardKey.toId(), FEE_100);
  }

  function test_setPoolOverride_revertsInvalidFee() public {
    // Fee with 12-bit component > 1000
    uint24 badFee = (1001 << 12) | 500;
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeeAdapter.InvalidFeeValue.selector);
    adapter.setPoolOverride(standardKey.toId(), badFee);
  }

  function test_poolOverride_takesPriorityOverPolicy() public {
    // Configure policy to return FEE_300 via baseline curve
    vm.startPrank(feeSetter);
    policy.setBaselineCurve(_buildCurve());
    // Set pool override to FEE_500
    adapter.setPoolOverride(standardKey.toId(), FEE_500);
    vm.stopPrank();

    assertEq(adapter.getFee(standardKey), FEE_500);
    vm.snapshotGasLastCall("adapter.getFee - pool override hit");
  }

  // ============ Adapter: Fee Triggering ============

  function test_triggerFeeUpdate_success() public {
    vm.prank(feeSetter);
    policy.setBaselineCurve(_buildCurve());

    vm.expectEmit(true, true, false, true, address(adapter));
    emit IV4FeeAdapter.FeeUpdateTriggered(alice, standardKey.toId(), FEE_300);
    vm.prank(alice);
    adapter.triggerFeeUpdate(standardKey);
    vm.snapshotGasLastCall("adapter.triggerFeeUpdate - single pool");

    assertEq(poolManager.getProtocolFee(standardKey.toId()), FEE_300);
  }

  function test_triggerFeeUpdate_skipsUninitializedPool() public {
    PoolKey memory uninitKey = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 500,
      tickSpacing: 10,
      hooks: IHooks(address(0))
    });
    // Don't initialize -should not revert
    adapter.triggerFeeUpdate(uninitKey);
    assertEq(poolManager.getProtocolFee(uninitKey.toId()), 0);
  }

  function testFuzz_triggerFeeUpdate_permissionless(address caller) public {
    vm.assume(caller != address(0));
    vm.prank(feeSetter);
    policy.setBaselineCurve(_buildCurve());

    vm.prank(caller);
    adapter.triggerFeeUpdate(standardKey);
    assertEq(poolManager.getProtocolFee(standardKey.toId()), FEE_300);
  }

  function test_batchTriggerFeeUpdate_success() public {
    vm.prank(feeSetter);
    policy.setBaselineCurve(_buildCurve());

    PoolKey[] memory keys = new PoolKey[](2);
    keys[0] = standardKey;
    keys[1] = hookKey;

    adapter.batchTriggerFeeUpdate(keys);
    vm.snapshotGasLastCall("adapter.batchTriggerFeeUpdate - two pools");

    assertEq(poolManager.getProtocolFee(standardKey.toId()), FEE_300);
    assertEq(poolManager.getProtocolFee(hookKey.toId()), FEE_300);
  }

  // ============ Adapter: Collection ============

  function test_collect_success() public {
    Currency c = Currency.wrap(address(token0));
    uint256 amount = 1000e18;
    token0.mint(address(poolManager), amount);
    poolManager.setProtocolFeesAccrued(c, amount);

    IV4FeeAdapter.CollectParams[] memory params = new IV4FeeAdapter.CollectParams[](1);
    params[0] = IV4FeeAdapter.CollectParams({currency: c, amount: amount});

    vm.expectEmit(true, false, false, true, address(adapter));
    emit IV4FeeAdapter.FeesCollected(c, amount);
    adapter.collect(params);
    vm.snapshotGasLastCall("adapter.collect - single currency");

    assertEq(token0.balanceOf(tokenJar), amount);
  }

  function test_collect_zeroCollectsAll() public {
    Currency c = Currency.wrap(address(token0));
    uint256 amount = 500e18;
    token0.mint(address(poolManager), amount);
    poolManager.setProtocolFeesAccrued(c, amount);

    IV4FeeAdapter.CollectParams[] memory params = new IV4FeeAdapter.CollectParams[](1);
    params[0] = IV4FeeAdapter.CollectParams({currency: c, amount: 0});

    adapter.collect(params);
    assertEq(token0.balanceOf(tokenJar), amount);
  }

  // ============ Policy: Construction ============

  function test_policy_constructor() public view {
    assertEq(address(policy.POOL_MANAGER()), address(poolManager));
    assertEq(policy.feeSetter(), feeSetter);
    assertEq(policy.CUSTOM_ACCOUNTING_MASK(), 0xF);
  }

  // ============ Policy: Admin ============

  function test_setFeeSetter_policy() public {
    vm.expectEmit(true, true, false, false, address(policy));
    emit IV4FeePolicy.FeeSetterUpdated(feeSetter, alice);
    vm.prank(owner);
    policy.setFeeSetter(alice);
    assertEq(policy.feeSetter(), alice);
  }

  function test_setFeeSetter_policy_revertsUnauthorized() public {
    vm.prank(alice);
    vm.expectRevert("UNAUTHORIZED");
    policy.setFeeSetter(alice);
  }

  // ============ Policy: isCustomAccounting ============

  function test_isCustomAccounting_noHook() public view {
    assertFalse(policy.isCustomAccounting(address(0)));
  }

  function test_isCustomAccounting_noDeltaFlags() public view {
    // Address with only bit 7 set (beforeSwap) -no custom accounting
    assertFalse(policy.isCustomAccounting(address(uint160(1 << 7))));
  }

  function test_isCustomAccounting_beforeSwapReturnsDelta() public view {
    // Bit 3 = BEFORE_SWAP_RETURNS_DELTA
    assertTrue(policy.isCustomAccounting(address(uint160(1 << 3))));
  }

  function test_isCustomAccounting_afterSwapReturnsDelta() public view {
    // Bit 2 = AFTER_SWAP_RETURNS_DELTA
    assertTrue(policy.isCustomAccounting(address(uint160(1 << 2))));
  }

  function test_isCustomAccounting_allDeltaFlags() public view {
    // Bits 0-3 all set
    assertTrue(policy.isCustomAccounting(address(uint160(0xF))));
  }

  function testFuzz_isCustomAccounting(uint160 addr) public view {
    bool expected = addr & 0xF != 0;
    assertEq(policy.isCustomAccounting(address(addr)), expected);
  }

  // ============ Policy: Baseline Curve ============

  function test_setBaselineCurve_success() public {
    CurveBreakpoint[] memory curve = _buildCurve();
    vm.expectEmit(false, false, false, true, address(policy));
    emit IV4FeePolicy.BaselineCurveUpdated(4);
    vm.prank(feeSetter);
    policy.setBaselineCurve(curve);

    vm.snapshotGasLastCall("policy.setBaselineCurve - four breakpoints");
    assertEq(policy.baselineCurveLength(), 4);
    (uint24 floor, uint24 fee) = policy.baselineCurve(2);
    assertEq(floor, 3000);
    assertEq(fee, FEE_300);
  }

  function test_setBaselineCurve_revertsEmpty() public {
    CurveBreakpoint[] memory empty = new CurveBreakpoint[](0);
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.EmptyCurve.selector);
    policy.setBaselineCurve(empty);
  }

  function test_setBaselineCurve_revertsNotAscending() public {
    CurveBreakpoint[] memory curve = new CurveBreakpoint[](2);
    curve[0] = CurveBreakpoint({lpFeeFloor: 3000, protocolFee: FEE_300});
    curve[1] = CurveBreakpoint({lpFeeFloor: 500, protocolFee: FEE_200}); // not ascending
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.CurveNotAscending.selector);
    policy.setBaselineCurve(curve);
  }

  function test_setBaselineCurve_revertsInvalidFee() public {
    CurveBreakpoint[] memory curve = new CurveBreakpoint[](1);
    curve[0] = CurveBreakpoint({lpFeeFloor: 0, protocolFee: (1001 << 12) | 1001});
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.InvalidFeeValue.selector);
    policy.setBaselineCurve(curve);
  }

  function test_setBaselineCurve_revertsUnauthorized() public {
    vm.prank(alice);
    vm.expectRevert(IV4FeePolicy.Unauthorized.selector);
    policy.setBaselineCurve(_buildCurve());
  }

  function test_setBaselineCurve_replacesExisting() public {
    vm.startPrank(feeSetter);
    policy.setBaselineCurve(_buildCurve());
    assertEq(policy.baselineCurveLength(), 4);

    CurveBreakpoint[] memory newCurve = new CurveBreakpoint[](1);
    newCurve[0] = CurveBreakpoint({lpFeeFloor: 0, protocolFee: FEE_100});
    policy.setBaselineCurve(newCurve);
    assertEq(policy.baselineCurveLength(), 1);
    vm.stopPrank();
  }

  // ============ Policy: computeFee - static native math path ============

  function test_computeFee_staticNativeMath_baselineCurve() public {
    vm.prank(feeSetter);
    policy.setBaselineCurve(_buildCurve());

    // key.fee = 3000 -> should match the 3000 breakpoint -> FEE_300
    assertEq(policy.computeFee(standardKey), FEE_300);
    vm.snapshotGasLastCall("policy.computeFee - static native math baseline curve");
  }

  function test_computeFee_staticNativeMath_baselineCurve_lowFee() public {
    vm.prank(feeSetter);
    policy.setBaselineCurve(_buildCurve());

    PoolKey memory lowFeeKey = standardKey;
    lowFeeKey.fee = 100;
    poolManager.mockInitialize(lowFeeKey);

    // key.fee = 100, floor 0 matches -> FEE_100
    assertEq(policy.computeFee(lowFeeKey), FEE_100);
  }

  function test_computeFee_staticNativeMath_pairFeeOverridesCurve() public {
    vm.startPrank(feeSetter);
    policy.setBaselineCurve(_buildCurve());
    policy.setPairFee(standardKey.currency0, standardKey.currency1, FEE_500);
    vm.stopPrank();

    // Pair fee should override baseline curve
    assertEq(policy.computeFee(standardKey), FEE_500);
    vm.snapshotGasLastCall("policy.computeFee - static native math pair fee");
  }

  function test_computeFee_staticNativeMath_emptyCurveReturnsZero() public view {
    assertEq(policy.computeFee(standardKey), 0);
  }

  function test_computeFee_staticNativeMath_hookWithoutDeltaFlags() public {
    vm.prank(feeSetter);
    policy.setBaselineCurve(_buildCurve());

    // hookKey has address with bit 7 set but bits 0-3 clear -> StaticNativeMath path
    assertEq(policy.computeFee(hookKey), FEE_300);
  }

  // ============ Policy: computeFee - classified path ============

  function test_computeFee_classified_familyDefault() public {
    // Create a pool with a custom-accounting hook (bit 2 = afterSwapReturnsDelta)
    address customHook = address(uint160((1 << 7) | (1 << 2))); // beforeSwap +
    // afterSwapReturnsDelta
    PoolKey memory customKey = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(customHook)
    });
    poolManager.mockInitialize(customKey);

    vm.startPrank(feeSetter);
    policy.setBaselineCurve(_buildCurve());
    policy.setHookFamily(customHook, 1);
    policy.setFamilyDefault(1, FEE_200);
    vm.stopPrank();

    assertEq(policy.computeFee(customKey), FEE_200);
    vm.snapshotGasLastCall("policy.computeFee - classified family default");
  }

  function test_computeFee_classified_pairFeeTimesMultiplier() public {
    address customHook = address(uint160((1 << 7) | (1 << 2)));
    PoolKey memory customKey = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(customHook)
    });
    poolManager.mockInitialize(customKey);

    vm.startPrank(feeSetter);
    policy.setHookFamily(customHook, 1);
    policy.setPairFee(customKey.currency0, customKey.currency1, FEE_200);
    policy.setFamilyMultiplier(1, 5000); // 50%
    vm.stopPrank();

    // FEE_200 = 200|200, multiplied by 50% = 100|100 = FEE_100
    assertEq(policy.computeFee(customKey), FEE_100);
    vm.snapshotGasLastCall("policy.computeFee - classified pairFee * multiplier");
  }

  function test_computeFee_classified_multiplierClamps() public {
    address customHook = address(uint160((1 << 7) | (1 << 2)));
    PoolKey memory customKey = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(customHook)
    });
    poolManager.mockInitialize(customKey);

    vm.startPrank(feeSetter);
    policy.setHookFamily(customHook, 1);
    policy.setPairFee(customKey.currency0, customKey.currency1, FEE_1000);
    policy.setFamilyMultiplier(1, 20_000); // 2x -> would be 2000, clamped to 1000
    vm.stopPrank();

    assertEq(policy.computeFee(customKey), FEE_1000);
  }

  function test_computeFee_classified_unclassifiedFallsToDefault() public {
    address customHook = address(uint160(1 << 2)); // custom accounting, no family set
    PoolKey memory customKey = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(customHook)
    });
    poolManager.mockInitialize(customKey);

    vm.prank(feeSetter);
    policy.setDefaultFee(FEE_100);

    assertEq(policy.computeFee(customKey), FEE_100);
    vm.snapshotGasLastCall("policy.computeFee - classified unclassified -> defaultFee");
  }

  function test_computeFee_classified_unclassifiedNoDefaultReturnsZero() public {
    address customHook = address(uint160(1 << 2));
    PoolKey memory customKey = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(customHook)
    });
    poolManager.mockInitialize(customKey);

    assertEq(policy.computeFee(customKey), 0);
  }

  function test_computeFee_dynamicFee_requiresClassification() public {
    // Dynamic fee pool with no hook -> classified path, hookFamilyId[address(0)] = 0
    vm.prank(feeSetter);
    policy.setDefaultFee(FEE_100);

    assertEq(policy.computeFee(dynamicKey), FEE_100);
  }

  function test_computeFee_dynamicFee_withFamily() public {
    // Dynamic fee pool at address(0) -familyId lookup for address(0)
    vm.startPrank(feeSetter);
    policy.setHookFamily(address(0), 2);
    policy.setFamilyDefault(2, FEE_300);
    vm.stopPrank();

    assertEq(policy.computeFee(dynamicKey), FEE_300);
  }

  // ============ Policy: Hook Self-Report ============

  function test_computeFee_selfReport_usedWhenNoGovernanceOverride() public {
    // Deploy a self-reporting hook at an address with custom accounting flags
    uint160 flags = (1 << 7) | (1 << 2); // beforeSwap + afterSwapReturnsDelta
    address hookAddr = address(flags);
    MockFeeClassifiedHook impl = new MockFeeClassifiedHook(3);
    vm.etch(hookAddr, address(impl).code);

    PoolKey memory selfReportKey = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(hookAddr)
    });
    poolManager.mockInitialize(selfReportKey);

    // Set family 3's default fee
    vm.prank(feeSetter);
    policy.setFamilyDefault(3, FEE_200);

    // Hook self-reports family 3, policy should use it
    assertEq(policy.computeFee(selfReportKey), FEE_200);
    vm.snapshotGasLastCall("policy.computeFee - classified self-report");
  }

  function test_computeFee_selfReport_governanceOverrideWins() public {
    uint160 flags = (1 << 7) | (1 << 2);
    address hookAddr = address(flags);
    MockFeeClassifiedHook impl = new MockFeeClassifiedHook(3);
    vm.etch(hookAddr, address(impl).code);

    PoolKey memory key = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(hookAddr)
    });
    poolManager.mockInitialize(key);

    vm.startPrank(feeSetter);
    policy.setFamilyDefault(3, FEE_200); // self-report family
    policy.setFamilyDefault(5, FEE_500); // governance family
    policy.setHookFamily(hookAddr, 5); // governance override
    vm.stopPrank();

    assertEq(policy.computeFee(key), FEE_500);
  }

  function test_computeFee_selfReport_revertingHookFallsToDefault() public {
    uint160 flags = (1 << 7) | (1 << 2);
    address hookAddr = address(flags);
    RevertingHook impl = new RevertingHook();
    vm.etch(hookAddr, address(impl).code);

    PoolKey memory key = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(hookAddr)
    });
    poolManager.mockInitialize(key);

    vm.prank(feeSetter);
    policy.setDefaultFee(FEE_100);

    // Hook reverts -> treated as unclassified -> defaultFee
    assertEq(policy.computeFee(key), FEE_100);
  }

  function test_computeFee_selfReport_griefingHookDoesNotDOS() public {
    uint160 flags = (1 << 7) | (1 << 2);
    address hookAddr = address(flags);
    GriefingHook impl = new GriefingHook();
    vm.etch(hookAddr, address(impl).code);

    PoolKey memory key = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(hookAddr)
    });
    poolManager.mockInitialize(key);

    vm.prank(feeSetter);
    policy.setDefaultFee(FEE_100);

    // Gas-capped call should fail gracefully -> defaultFee
    assertEq(policy.computeFee(key), FEE_100);
    vm.snapshotGasLastCall("policy.computeFee - classified griefing hook -> defaultFee");
  }

  // ============ Policy: Configuration Functions ============

  function test_setHookFamily_success() public {
    address hook = address(uint160(1 << 2));
    vm.expectEmit(true, false, false, true, address(policy));
    emit IV4FeePolicy.HookFamilySet(hook, 1);
    vm.prank(feeSetter);
    policy.setHookFamily(hook, 1);
    vm.snapshotGasLastCall("policy.setHookFamily");
    assertEq(policy.hookFamilyId(hook), 1);
  }

  function test_setHookFamily_overwrite() public {
    address hook = address(uint160(1 << 2));
    vm.startPrank(feeSetter);
    policy.setHookFamily(hook, 1);
    policy.setHookFamily(hook, 5);
    vm.stopPrank();
    assertEq(policy.hookFamilyId(hook), 5);
  }

  function test_setHookFamily_zeroUnclassifies() public {
    address hook = address(uint160(1 << 2));
    vm.startPrank(feeSetter);
    policy.setHookFamily(hook, 3);
    policy.setHookFamily(hook, 0);
    vm.stopPrank();
    assertEq(policy.hookFamilyId(hook), 0);
  }

  function test_setHookFamily_revertsUnauthorized() public {
    vm.prank(alice);
    vm.expectRevert(IV4FeePolicy.Unauthorized.selector);
    policy.setHookFamily(address(1), 1);
  }

  function test_setDefaultFee_success() public {
    vm.expectEmit(false, false, false, true, address(policy));
    emit IV4FeePolicy.DefaultFeeUpdated(FEE_100);
    vm.prank(feeSetter);
    policy.setDefaultFee(FEE_100);
  }

  function test_setDefaultFee_revertsInvalidFee() public {
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.InvalidFeeValue.selector);
    policy.setDefaultFee((2000 << 12) | 2000);
  }

  function test_setFamilyDefault_success() public {
    vm.expectEmit(true, false, false, true, address(policy));
    emit IV4FeePolicy.FamilyDefaultUpdated(1, FEE_300);
    vm.prank(feeSetter);
    policy.setFamilyDefault(1, FEE_300);
    vm.snapshotGasLastCall("policy.setFamilyDefault");
    assertEq(policy.familyDefaults(1), FEE_300);
  }

  function test_setFamilyDefault_revertsZeroFamily() public {
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.InvalidFamilyId.selector);
    policy.setFamilyDefault(0, FEE_100);
  }

  function test_setFamilyMultiplier_success() public {
    vm.expectEmit(true, false, false, true, address(policy));
    emit IV4FeePolicy.FamilyMultiplierUpdated(2, 5000);
    vm.prank(feeSetter);
    policy.setFamilyMultiplier(2, 5000);
    vm.snapshotGasLastCall("policy.setFamilyMultiplier");
    assertEq(policy.familyMultiplierBps(2), 5000);
  }

  function test_setFamilyMultiplier_revertsZeroFamily() public {
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.InvalidFamilyId.selector);
    policy.setFamilyMultiplier(0, 10_000);
  }

  function test_setPairFee_success() public {
    bytes32 ph = _pairHash();
    vm.expectEmit(true, false, false, true, address(policy));
    emit IV4FeePolicy.PairFeeUpdated(ph, FEE_200);
    vm.prank(feeSetter);
    policy.setPairFee(standardKey.currency0, standardKey.currency1, FEE_200);
    vm.snapshotGasLastCall("policy.setPairFee");
    assertEq(policy.pairFees(ph), FEE_200);
  }

  function test_setPairFee_revertsCurrenciesOutOfOrder() public {
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.CurrenciesOutOfOrder.selector);
    policy.setPairFee(standardKey.currency1, standardKey.currency0, FEE_200);
  }

  function test_setPairFee_revertsInvalidFee() public {
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.InvalidFeeValue.selector);
    policy.setPairFee(standardKey.currency0, standardKey.currency1, (1001 << 12) | 500);
  }

  // ============ Policy: Sentinel Encoding ============

  function test_sentinel_setZeroIsExplicitZero() public {
    // setFamilyDefault(1, 0) stores sentinel -explicit zero fee, not "unset"
    vm.startPrank(feeSetter);
    policy.setFamilyDefault(1, FEE_200);
    assertEq(policy.familyDefaults(1), FEE_200);

    policy.setFamilyDefault(1, 0);
    assertEq(policy.familyDefaults(1), type(uint24).max); // sentinel in storage
    vm.stopPrank();

    // computeFee decodes sentinel to 0 -explicit zero, does not fall through
    address customHook = address(uint160((1 << 7) | (1 << 2)));
    PoolKey memory customKey = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(customHook)
    });
    poolManager.mockInitialize(customKey);

    vm.startPrank(feeSetter);
    policy.setHookFamily(customHook, 1);
    policy.setDefaultFee(FEE_500); // would be used if familyDefault were unset
    vm.stopPrank();

    // Family 1 has explicit zero -> 0, NOT the defaultFee of FEE_500
    assertEq(policy.computeFee(customKey), 0);
  }

  function test_sentinel_clearFallsThrough() public {
    // clearFamilyDefault deletes storage -> falls through to defaultFee
    address customHook = address(uint160((1 << 7) | (1 << 2)));
    PoolKey memory customKey = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(customHook)
    });
    poolManager.mockInitialize(customKey);

    vm.startPrank(feeSetter);
    policy.setHookFamily(customHook, 1);
    policy.setFamilyDefault(1, FEE_200);
    policy.setDefaultFee(FEE_500);
    vm.stopPrank();

    assertEq(policy.computeFee(customKey), FEE_200); // familyDefault wins

    vm.prank(feeSetter);
    policy.clearFamilyDefault(1);

    assertEq(policy.familyDefaults(1), 0); // storage is 0, not sentinel
    assertEq(policy.computeFee(customKey), FEE_500); // falls through to defaultFee
  }

  // ============ Policy: Clear Functions ============

  function test_clearDefaultFee() public {
    vm.startPrank(feeSetter);
    policy.setDefaultFee(FEE_200);
    assertEq(policy.defaultFee(), FEE_200);

    policy.clearDefaultFee();
    assertEq(policy.defaultFee(), 0); // storage deleted, not sentinel
    vm.stopPrank();
  }

  function test_clearFamilyMultiplier() public {
    vm.startPrank(feeSetter);
    policy.setFamilyMultiplier(1, 5000);
    assertEq(policy.familyMultiplierBps(1), 5000);

    policy.clearFamilyMultiplier(1);
    assertEq(policy.familyMultiplierBps(1), 0);
    vm.stopPrank();
  }

  function test_clearPairFee_fallsThroughToCurve() public {
    vm.startPrank(feeSetter);
    policy.setBaselineCurve(_buildCurve());
    policy.setPairFee(standardKey.currency0, standardKey.currency1, FEE_500);
    vm.stopPrank();

    assertEq(policy.computeFee(standardKey), FEE_500); // pair fee wins

    vm.prank(feeSetter);
    policy.clearPairFee(standardKey.currency0, standardKey.currency1);

    assertEq(policy.pairFees(_pairHash()), 0); // storage deleted
    assertEq(policy.computeFee(standardKey), FEE_300); // back to baseline curve
  }

  function test_clearPairFee_revertsCurrenciesOutOfOrder() public {
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.CurrenciesOutOfOrder.selector);
    policy.clearPairFee(standardKey.currency1, standardKey.currency0);
  }

  // ============ Integration: Full Waterfall ============

  function test_integration_fullWaterfall() public {
    address customHook = address(uint160((1 << 7) | (1 << 2)));
    PoolKey memory customKey = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(customHook)
    });
    poolManager.mockInitialize(customKey);

    vm.startPrank(feeSetter);
    policy.setBaselineCurve(_buildCurve());
    policy.setDefaultFee(FEE_100);
    policy.setHookFamily(customHook, 1);
    policy.setFamilyDefault(1, FEE_200);
    policy.setPairFee(customKey.currency0, customKey.currency1, FEE_300);
    policy.setFamilyMultiplier(1, 10_000); // 1x
    vm.stopPrank();

    // StandardKey -> StaticNativeMath -> pair fee overrides curve -> FEE_300
    assertEq(adapter.getFee(standardKey), FEE_300);

    // CustomKey -> Classified -> pair fee × multiplier -> FEE_300 × 1x = FEE_300
    assertEq(adapter.getFee(customKey), FEE_300);

    // Pool override beats everything
    vm.prank(feeSetter);
    adapter.setPoolOverride(standardKey.toId(), FEE_1000);
    assertEq(adapter.getFee(standardKey), FEE_1000);
  }

  function test_integration_triggerAndCollect() public {
    Currency c = Currency.wrap(address(token0));
    uint256 amount = 100e18;
    token0.mint(address(poolManager), amount);
    poolManager.setProtocolFeesAccrued(c, amount);

    vm.prank(feeSetter);
    policy.setBaselineCurve(_buildCurve());

    // Trigger fee update
    adapter.triggerFeeUpdate(standardKey);
    assertEq(poolManager.getProtocolFee(standardKey.toId()), FEE_300);

    // Collect fees
    IV4FeeAdapter.CollectParams[] memory params = new IV4FeeAdapter.CollectParams[](1);
    params[0] = IV4FeeAdapter.CollectParams({currency: c, amount: 0});
    adapter.collect(params);
    assertEq(token0.balanceOf(tokenJar), amount);
  }

  // ============ Edge Cases ============

  function test_edge_maxProtocolFee() public {
    vm.prank(feeSetter);
    adapter.setPoolOverride(standardKey.toId(), FEE_1000);
    assertEq(adapter.getFee(standardKey), FEE_1000);
  }

  function test_edge_asymmetricFee() public {
    uint24 asymmetric = (500 << 12) | 200; // 500 pips 1->0, 200 pips 0->1
    vm.prank(feeSetter);
    adapter.setPoolOverride(standardKey.toId(), asymmetric);

    adapter.triggerFeeUpdate(standardKey);
    assertEq(poolManager.getProtocolFee(standardKey.toId()), asymmetric);
  }

  function test_edge_policySwap() public {
    vm.prank(feeSetter);
    policy.setBaselineCurve(_buildCurve());

    assertEq(adapter.getFee(standardKey), FEE_300);

    // Deploy new policy with different curve
    vm.startPrank(owner);
    V4FeePolicy newPolicy = new V4FeePolicy(IPoolManager(address(poolManager)));
    newPolicy.setFeeSetter(feeSetter);
    adapter.setPolicy(newPolicy);
    vm.stopPrank();

    // New policy has no curve -> 0
    assertEq(adapter.getFee(standardKey), 0);
  }
}
