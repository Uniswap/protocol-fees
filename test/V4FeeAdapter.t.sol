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
import {FlagRule, FeeBucket} from "../src/interfaces/IV4FeePolicy.sol";
import {HookFeeFlags} from "../src/libraries/HookFeeFlags.sol";
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

  /// @dev Slope value chosen so that `standardKey.fee = 3000` yields `FEE_300`
  /// (300 pips per direction) under a single bucket starting at floor 0:
  /// `0 + 100_000 × 3000 / 1_000_000 = 300`.
  uint32 internal constant TEST_BETA_PIPS = 100_000;

  /// @dev Returns a single-bucket array `[(0, 0, betaPips)]`. Equivalent in math to a
  /// pre-bucket-era global multiplier: `protocolFee = 0 + betaPips * lpFee / 1_000_000`.
  /// Caller is responsible for the prank.
  function _singleBucketSlope(uint32 betaPips) internal pure returns (FeeBucket[] memory bs) {
    bs = new FeeBucket[](1);
    bs[0] = FeeBucket({lpFeeFloor: 0, alphaPips: 0, betaPips: betaPips});
  }

  /// @dev Returns a single-bucket array `[(0, alphaPips, 0)]` — flat fee for any LP fee.
  function _singleBucketFlat(uint24 alphaPips) internal pure returns (FeeBucket[] memory bs) {
    bs = new FeeBucket[](1);
    bs[0] = FeeBucket({lpFeeFloor: 0, alphaPips: alphaPips, betaPips: 0});
  }

  /// @dev As above but pranks feeSetter for one-off setups.
  function _setSingleBucketSlope(uint32 betaPips) internal {
    vm.prank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(betaPips));
  }

  /// @dev Adjusted Configuration B from the design discussion. All alpha values stay at
  /// or below MAX_PROTOCOL_FEE = 1000 (the per-bucket cap). Continuity-preserving:
  /// each bucket starts at the previous bucket's endpoint.
  ///   bucket 0: [0, 100)         flat 0
  ///   bucket 1: [100, 500)       slope 10% (alpha 0, beta 100_000)
  ///   bucket 2: [500, 3000)      starts at 40, slope 20% (alpha 40, beta 200_000)
  ///   bucket 3: [3000, 10_000)   starts at 540, slope 15% (alpha 540, beta 150_000)
  ///   bucket 4: [10_000, ∞)      flat ceiling at MAX_PROTOCOL_FEE
  function _bucketsConfigB() internal pure returns (FeeBucket[] memory bs) {
    bs = new FeeBucket[](5);
    bs[0] = FeeBucket({lpFeeFloor: 0, alphaPips: 0, betaPips: 0});
    bs[1] = FeeBucket({lpFeeFloor: 100, alphaPips: 0, betaPips: 100_000});
    bs[2] = FeeBucket({lpFeeFloor: 500, alphaPips: 40, betaPips: 200_000});
    bs[3] = FeeBucket({lpFeeFloor: 3000, alphaPips: 540, betaPips: 150_000});
    bs[4] = FeeBucket({lpFeeFloor: 10_000, alphaPips: 1000, betaPips: 0});
  }

  function _pairHash() internal view returns (bytes32) {
    return keccak256(
      abi.encodePacked(
        Currency.unwrap(standardKey.currency0), Currency.unwrap(standardKey.currency1)
      )
    );
  }

  /// @dev Deploy a mock hook at a specific address using vm.etch.
  /// The lowest 14 bits of the address encode hook permissions.
  function _deployHookAt(uint160 addrFlags, uint256 feeFlags) internal returns (address) {
    address hookAddr = address(addrFlags);
    MockFeeClassifiedHook impl = new MockFeeClassifiedHook(feeFlags);
    vm.etch(hookAddr, address(impl).code);
    vm.store(hookAddr, bytes32(0), bytes32(feeFlags));
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
    policy.setFeeBuckets(_singleBucketSlope(TEST_BETA_PIPS));
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
    policy.setFeeBuckets(_singleBucketSlope(TEST_BETA_PIPS));

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
    // Configure policy to return FEE_300 via the multiplier path
    vm.startPrank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(TEST_BETA_PIPS));
    // Set pool override to FEE_500
    adapter.setPoolOverride(standardKey.toId(), FEE_500);
    vm.stopPrank();

    assertEq(adapter.getFee(standardKey), FEE_500);
    vm.snapshotGasLastCall("adapter.getFee - pool override hit");
  }

  // ============ Adapter: Fee Triggering ============

  function test_triggerFeeUpdate_success() public {
    vm.prank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(TEST_BETA_PIPS));

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
    policy.setFeeBuckets(_singleBucketSlope(TEST_BETA_PIPS));

    vm.prank(caller);
    adapter.triggerFeeUpdate(standardKey);
    assertEq(poolManager.getProtocolFee(standardKey.toId()), FEE_300);
  }

  function test_batchTriggerFeeUpdate_success() public {
    vm.prank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(TEST_BETA_PIPS));

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

  // ============ Policy: Fee Buckets ============

  function test_setFeeBuckets_success() public {
    FeeBucket[] memory bs = _singleBucketSlope(TEST_BETA_PIPS);

    vm.expectEmit(false, false, false, true, address(policy));
    emit IV4FeePolicy.FeeBucketsUpdated(1);
    vm.prank(feeSetter);
    policy.setFeeBuckets(bs);

    vm.snapshotGasLastCall("policy.setFeeBuckets - 1 bucket");
    assertEq(policy.feeBucketsLength(), 1);
    (uint24 floor, uint24 alpha, uint32 beta) = policy.feeBucket(0);
    assertEq(floor, 0);
    assertEq(alpha, 0);
    assertEq(beta, TEST_BETA_PIPS);
  }

  function test_setFeeBuckets_5buckets_configurationB() public {
    FeeBucket[] memory bs = _bucketsConfigB();

    vm.expectEmit(false, false, false, true, address(policy));
    emit IV4FeePolicy.FeeBucketsUpdated(5);
    vm.prank(feeSetter);
    policy.setFeeBuckets(bs);

    vm.snapshotGasLastCall("policy.setFeeBuckets - 5 buckets (configuration B)");
    assertEq(policy.feeBucketsLength(), 5);
  }

  function test_setFeeBuckets_revertsEmpty() public {
    FeeBucket[] memory bs = new FeeBucket[](0);
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.EmptyBuckets.selector);
    policy.setFeeBuckets(bs);
  }

  function test_setFeeBuckets_revertsNotAscending() public {
    FeeBucket[] memory bs = new FeeBucket[](2);
    bs[0] = FeeBucket({lpFeeFloor: 100, alphaPips: 0, betaPips: 0});
    bs[1] = FeeBucket({lpFeeFloor: 50, alphaPips: 0, betaPips: 0});
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.BucketsNotAscending.selector);
    policy.setFeeBuckets(bs);
  }

  function test_setFeeBuckets_revertsEqualFloors() public {
    // Strict ascending: equal floors must also revert.
    FeeBucket[] memory bs = new FeeBucket[](2);
    bs[0] = FeeBucket({lpFeeFloor: 100, alphaPips: 0, betaPips: 0});
    bs[1] = FeeBucket({lpFeeFloor: 100, alphaPips: 0, betaPips: 0});
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.BucketsNotAscending.selector);
    policy.setFeeBuckets(bs);
  }

  function test_setFeeBuckets_revertsAlphaTooLarge() public {
    FeeBucket[] memory bs = new FeeBucket[](1);
    bs[0] = FeeBucket({lpFeeFloor: 0, alphaPips: 1001, betaPips: 0});
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.InvalidFeeValue.selector);
    policy.setFeeBuckets(bs);
  }

  function test_setFeeBuckets_revertsBetaTooLarge() public {
    FeeBucket[] memory bs = new FeeBucket[](1);
    bs[0] = FeeBucket({lpFeeFloor: 0, alphaPips: 0, betaPips: 1_000_000_001});
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.MultiplierTooLarge.selector);
    policy.setFeeBuckets(bs);
  }

  function test_setFeeBuckets_revertsTooManyBuckets() public {
    FeeBucket[] memory bs = new FeeBucket[](17);
    for (uint256 i; i < 17; ++i) {
      bs[i] = FeeBucket({lpFeeFloor: uint24(i * 100), alphaPips: 0, betaPips: 0});
    }
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.TooManyBuckets.selector);
    policy.setFeeBuckets(bs);
  }

  function test_setFeeBuckets_acceptsAlphaBoundary() public {
    FeeBucket[] memory bs = new FeeBucket[](1);
    bs[0] = FeeBucket({lpFeeFloor: 0, alphaPips: 1000, betaPips: 0});
    vm.prank(feeSetter);
    policy.setFeeBuckets(bs);
    (, uint24 alpha,) = policy.feeBucket(0);
    assertEq(alpha, 1000);
  }

  function test_setFeeBuckets_acceptsBetaBoundary() public {
    FeeBucket[] memory bs = new FeeBucket[](1);
    bs[0] = FeeBucket({lpFeeFloor: 0, alphaPips: 0, betaPips: 1_000_000_000});
    vm.prank(feeSetter);
    policy.setFeeBuckets(bs);
    (,, uint32 beta) = policy.feeBucket(0);
    assertEq(beta, 1_000_000_000);
  }

  function test_setFeeBuckets_acceptsMaxBuckets() public {
    FeeBucket[] memory bs = new FeeBucket[](16);
    for (uint256 i; i < 16; ++i) {
      bs[i] = FeeBucket({lpFeeFloor: uint24(i * 100), alphaPips: 0, betaPips: 0});
    }
    vm.prank(feeSetter);
    policy.setFeeBuckets(bs);
    assertEq(policy.feeBucketsLength(), 16);
  }

  function test_setFeeBuckets_revertsUnauthorized() public {
    vm.prank(alice);
    vm.expectRevert(IV4FeePolicy.Unauthorized.selector);
    policy.setFeeBuckets(_singleBucketSlope(TEST_BETA_PIPS));
  }

  function test_setFeeBuckets_replacesExisting() public {
    vm.startPrank(feeSetter);
    policy.setFeeBuckets(_bucketsConfigB());
    assertEq(policy.feeBucketsLength(), 5);

    policy.setFeeBuckets(_singleBucketSlope(TEST_BETA_PIPS));
    assertEq(policy.feeBucketsLength(), 1);
    vm.stopPrank();
  }

  function test_clearFeeBuckets() public {
    vm.startPrank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(TEST_BETA_PIPS));
    assertEq(policy.feeBucketsLength(), 1);

    vm.expectEmit(false, false, false, true, address(policy));
    emit IV4FeePolicy.FeeBucketsUpdated(0);
    policy.clearFeeBuckets();
    vm.stopPrank();

    assertEq(policy.feeBucketsLength(), 0);
    // With no buckets and no pair fee, computeFee on standardKey returns 0.
    assertEq(policy.computeFee(standardKey), 0);
  }

  function test_clearFeeBuckets_revertsUnauthorized() public {
    vm.prank(alice);
    vm.expectRevert(IV4FeePolicy.Unauthorized.selector);
    policy.clearFeeBuckets();
  }

  // ============ Policy: computeFee - static native math path ============

  function test_computeFee_staticNativeMath_singleBucketSlope() public {
    vm.prank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(TEST_BETA_PIPS));

    // key.fee = 3000, single bucket (0, 0, 100_000) -> 0 + 100_000 * 3000 / 1_000_000 = 300
    assertEq(policy.computeFee(standardKey), FEE_300);
    vm.snapshotGasLastCall("policy.computeFee - static native math buckets");
  }

  function test_computeFee_staticNativeMath_singleBucketSlope_lowFee() public {
    vm.prank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(TEST_BETA_PIPS));

    PoolKey memory lowFeeKey = standardKey;
    lowFeeKey.fee = 100;
    poolManager.mockInitialize(lowFeeKey);

    // key.fee = 100 -> 100 * 100_000 / 1_000_000 = 10 per direction
    uint24 expected = (10 << 12) | 10;
    assertEq(policy.computeFee(lowFeeKey), expected);
  }

  function test_computeFee_staticNativeMath_pairFeeOverridesBuckets() public {
    vm.startPrank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(TEST_BETA_PIPS));
    policy.setPairFee(standardKey.currency0, standardKey.currency1, FEE_500);
    vm.stopPrank();

    // Pair fee should override the bucket-derived fee
    assertEq(policy.computeFee(standardKey), FEE_500);
    vm.snapshotGasLastCall("policy.computeFee - static native math pair fee");
  }

  function test_computeFee_staticNativeMath_zeroBucketsReturnsZero() public view {
    assertEq(policy.computeFee(standardKey), 0);
  }

  function test_computeFee_staticNativeMath_hookWithoutDeltaFlags() public {
    vm.prank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(TEST_BETA_PIPS));

    // hookKey has address with bit 7 set but bits 0-3 clear -> StaticNativeMath path
    assertEq(policy.computeFee(hookKey), FEE_300);
  }

  // ============ Policy: computeFee bucket math ============

  function test_computeFee_staticNativeMath_singleBucketFlat() public {
    vm.prank(feeSetter);
    policy.setFeeBuckets(_singleBucketFlat(25));

    // alpha=25, beta=0 → flat 25 pips for any LP fee
    uint24 expected = (25 << 12) | 25;
    assertEq(policy.computeFee(standardKey), expected); // key.fee = 3000

    PoolKey memory zeroFeeKey = standardKey;
    zeroFeeKey.fee = 0;
    poolManager.mockInitialize(zeroFeeKey);
    // snap-to-lowest with delta = 0 → still alpha = 25
    assertEq(policy.computeFee(zeroFeeKey), expected);
  }

  function test_computeFee_staticNativeMath_singleBucket1to1() public {
    // 1:1 boundary: beta = 1_000_000 means protocol fee == LP fee
    FeeBucket[] memory bs = new FeeBucket[](1);
    bs[0] = FeeBucket({lpFeeFloor: 0, alphaPips: 0, betaPips: 1_000_000});
    vm.prank(feeSetter);
    policy.setFeeBuckets(bs);

    PoolKey memory k = standardKey;
    k.fee = 1000;
    poolManager.mockInitialize(k);
    // 1000 * 1_000_000 / 1_000_000 = 1000 per direction (clamp boundary)
    assertEq(policy.computeFee(k), FEE_1000);
  }

  function test_computeFee_staticNativeMath_clamps() public {
    FeeBucket[] memory bs = new FeeBucket[](1);
    bs[0] = FeeBucket({lpFeeFloor: 0, alphaPips: 0, betaPips: 1_000_000});
    vm.prank(feeSetter);
    policy.setFeeBuckets(bs);

    PoolKey memory k = standardKey;
    k.fee = 5000;
    poolManager.mockInitialize(k);
    // 5000 * 1 = 5000, clamped to MAX_PROTOCOL_FEE = 1000 per direction
    assertEq(policy.computeFee(k), FEE_1000);
  }

  function test_computeFee_staticNativeMath_zeroLpFee_alphaZero() public {
    vm.prank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(TEST_BETA_PIPS));

    PoolKey memory zeroFeeKey = standardKey;
    zeroFeeKey.fee = 0;
    poolManager.mockInitialize(zeroFeeKey);
    // alpha = 0 + beta * 0 / 1_000_000 = 0
    assertEq(policy.computeFee(zeroFeeKey), 0);
  }

  function test_computeFee_staticNativeMath_zeroLpFee_alphaNonzero() public {
    vm.prank(feeSetter);
    policy.setFeeBuckets(_singleBucketFlat(25));

    PoolKey memory zeroFeeKey = standardKey;
    zeroFeeKey.fee = 0;
    poolManager.mockInitialize(zeroFeeKey);
    uint24 expected = (25 << 12) | 25;
    assertEq(policy.computeFee(zeroFeeKey), expected);
  }

  function test_computeFee_staticNativeMath_snapToLowest() public {
    // Two buckets where the lowest floor is > 0. lpFee < floor_0 must snap to bucket 0.
    FeeBucket[] memory bs = new FeeBucket[](2);
    bs[0] = FeeBucket({lpFeeFloor: 100, alphaPips: 25, betaPips: 0});
    bs[1] = FeeBucket({lpFeeFloor: 500, alphaPips: 50, betaPips: 0});
    vm.prank(feeSetter);
    policy.setFeeBuckets(bs);

    PoolKey memory k = standardKey;
    k.fee = 50; // below floor_0 = 100
    poolManager.mockInitialize(k);

    // Snap to bucket 0 with delta = 0 -> alpha_0 = 25
    uint24 expected = (25 << 12) | 25;
    assertEq(policy.computeFee(k), expected);
  }

  function test_computeFee_staticNativeMath_continuousPiecewise() public {
    vm.prank(feeSetter);
    policy.setFeeBuckets(_bucketsConfigB());

    // Spot-check several lpFee values against the curve table:
    //   lpFee=50    bucket 0 (flat 0)            -> 0
    //   lpFee=100   bucket 1 starts (delta=0)    -> 0
    //   lpFee=500   bucket 2 starts (delta=0)    -> 40
    //   lpFee=3000  bucket 3 starts (delta=0)    -> 540
    //   lpFee=10000 bucket 4 starts (flat 1000)  -> 1000 (clamp territory)
    //   lpFee=200   bucket 1, delta=100          -> 0 + 100_000*100/1e6 = 10
    //   lpFee=1000  bucket 2, delta=500          -> 40 + 200_000*500/1e6 = 140
    //   lpFee=5000  bucket 3, delta=2000         -> 540 + 150_000*2000/1e6 = 840
    PoolKey memory k = standardKey;

    k.fee = 50;
    poolManager.mockInitialize(k);
    assertEq(policy.computeFee(k), 0);

    k.fee = 100;
    poolManager.mockInitialize(k);
    assertEq(policy.computeFee(k), 0);

    k.fee = 500;
    poolManager.mockInitialize(k);
    assertEq(policy.computeFee(k), (40 << 12) | 40);

    k.fee = 3000;
    assertEq(policy.computeFee(k), (540 << 12) | 540);

    k.fee = 10_000;
    poolManager.mockInitialize(k);
    assertEq(policy.computeFee(k), FEE_1000);

    k.fee = 200;
    poolManager.mockInitialize(k);
    assertEq(policy.computeFee(k), (10 << 12) | 10);

    k.fee = 1000;
    poolManager.mockInitialize(k);
    assertEq(policy.computeFee(k), (140 << 12) | 140);

    k.fee = 5000;
    poolManager.mockInitialize(k);
    assertEq(policy.computeFee(k), (840 << 12) | 840);
  }

  function test_computeFee_staticNativeMath_discontinuousPiecewise() public {
    // Intentional cliff: alpha jumps at the boundary
    FeeBucket[] memory bs = new FeeBucket[](2);
    bs[0] = FeeBucket({lpFeeFloor: 0, alphaPips: 25, betaPips: 0});
    bs[1] = FeeBucket({lpFeeFloor: 100, alphaPips: 100, betaPips: 0});
    vm.prank(feeSetter);
    policy.setFeeBuckets(bs);

    PoolKey memory k = standardKey;
    k.fee = 99;
    poolManager.mockInitialize(k);
    assertEq(policy.computeFee(k), (25 << 12) | 25);

    k.fee = 100;
    poolManager.mockInitialize(k);
    assertEq(policy.computeFee(k), (100 << 12) | 100);
  }

  function test_computeFee_staticNativeMath_pairFeeBeatsBuckets() public {
    vm.startPrank(feeSetter);
    policy.setFeeBuckets(_bucketsConfigB());
    policy.setPairFee(standardKey.currency0, standardKey.currency1, FEE_200);
    vm.stopPrank();

    // Pair fee wins over bucket-derived fee
    assertEq(policy.computeFee(standardKey), FEE_200);
  }

  function test_computeFee_dynamicFee_skipsBuckets() public {
    // Regression: a future routing bug must not evaluate buckets for DYNAMIC_FEE_FLAG.
    // Dynamic-fee pools must take the classified path.
    vm.startPrank(feeSetter);
    policy.setFeeBuckets(_bucketsConfigB());
    policy.setDefaultFee(FEE_100);
    vm.stopPrank();

    // dynamicKey.fee == LPFeeLibrary.DYNAMIC_FEE_FLAG -> classified -> defaultFee
    assertEq(policy.computeFee(dynamicKey), FEE_100);
  }

  function testFuzz_computeFee_staticNativeMath_buckets(uint24 lpFee) public {
    lpFee = uint24(bound(lpFee, 0, LPFeeLibrary.MAX_LP_FEE));
    vm.prank(feeSetter);
    policy.setFeeBuckets(_bucketsConfigB());

    PoolKey memory k = standardKey;
    k.fee = lpFee;
    poolManager.mockInitialize(k);

    uint24 fee = policy.computeFee(k);
    uint24 zeroForOne = fee & 0xFFF;
    uint24 oneForZero = fee >> 12;
    assertEq(zeroForOne, oneForZero); // symmetric: both 12-bit components equal
    assertLe(zeroForOne, ProtocolFeeLibrary.MAX_PROTOCOL_FEE);
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
    policy.setFamilyMultiplier(1, 500_000); // 50%
    vm.stopPrank();

    // FEE_200 = 200|200, multiplied by 50% = 100|100 = FEE_100
    assertEq(policy.computeFee(customKey), FEE_100);
    vm.snapshotGasLastCall("policy.computeFee - classified pairFee * multiplier");
  }

  function test_computeFee_classified_pairFeeAtMaxMultiplier() public {
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
    policy.setFamilyMultiplier(1, 1_000_000); // 100% (1x) -- the new ceiling
    vm.stopPrank();

    // FEE_1000 (1000|1000) * 1x = FEE_1000; setter validation guarantees the result
    // can never exceed MAX_PROTOCOL_FEE per direction.
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
    uint160 addrFlags = (1 << 7) | (1 << 2); // beforeSwap + afterSwapReturnsDelta
    address hookAddr = address(addrFlags);
    uint256 feeFlags = HookFeeFlags.TAKES_SWAP_SURPLUS;
    MockFeeClassifiedHook impl = new MockFeeClassifiedHook(feeFlags);
    vm.etch(hookAddr, address(impl).code);

    PoolKey memory selfReportKey = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(hookAddr)
    });
    poolManager.mockInitialize(selfReportKey);

    // Configure flag rule: TAKES_SWAP_SURPLUS -> family 3
    FlagRule[] memory rules = new FlagRule[](1);
    rules[0] = FlagRule({requiredFlags: HookFeeFlags.TAKES_SWAP_SURPLUS, familyId: 3});

    vm.startPrank(feeSetter);
    policy.setFlagRules(rules);
    policy.setFamilyDefault(3, FEE_200);
    vm.stopPrank();

    // Hook self-reports TAKES_SWAP_SURPLUS, rule maps to family 3
    assertEq(policy.computeFee(selfReportKey), FEE_200);
    vm.snapshotGasLastCall("policy.computeFee - classified flag-rule self-report");
  }

  function test_computeFee_selfReport_governanceOverrideWins() public {
    uint160 addrFlags = (1 << 7) | (1 << 2);
    address hookAddr = address(addrFlags);
    uint256 feeFlags = HookFeeFlags.TAKES_SWAP_SURPLUS;
    MockFeeClassifiedHook impl = new MockFeeClassifiedHook(feeFlags);
    vm.etch(hookAddr, address(impl).code);

    PoolKey memory key = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(hookAddr)
    });
    poolManager.mockInitialize(key);

    FlagRule[] memory rules = new FlagRule[](1);
    rules[0] = FlagRule({requiredFlags: HookFeeFlags.TAKES_SWAP_SURPLUS, familyId: 3});

    vm.startPrank(feeSetter);
    policy.setFlagRules(rules);
    policy.setFamilyDefault(3, FEE_200); // flag-rule family
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
    emit IV4FeePolicy.FamilyMultiplierUpdated(2, 500_000);
    vm.prank(feeSetter);
    policy.setFamilyMultiplier(2, 500_000);
    vm.snapshotGasLastCall("policy.setFamilyMultiplier");
    assertEq(policy.familyMultiplierPips(2), 500_000);
  }

  function test_setFamilyMultiplier_revertsZeroFamily() public {
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.InvalidFamilyId.selector);
    policy.setFamilyMultiplier(0, 100_000);
  }

  function test_setFamilyMultiplier_revertsTooLarge() public {
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.MultiplierTooLarge.selector);
    policy.setFamilyMultiplier(1, 1_000_001);
  }

  function test_setFamilyMultiplier_acceptsBoundary() public {
    vm.prank(feeSetter);
    policy.setFamilyMultiplier(1, 1_000_000);
    assertEq(policy.familyMultiplierPips(1), 1_000_000);
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
    policy.setFamilyMultiplier(1, 500_000);
    assertEq(policy.familyMultiplierPips(1), 500_000);

    policy.clearFamilyMultiplier(1);
    assertEq(policy.familyMultiplierPips(1), 0);
    vm.stopPrank();
  }

  function test_clearPairFee_fallsThroughToMultiplier() public {
    vm.startPrank(feeSetter);
    policy.setFeeBuckets(_singleBucketSlope(TEST_BETA_PIPS));
    policy.setPairFee(standardKey.currency0, standardKey.currency1, FEE_500);
    vm.stopPrank();

    assertEq(policy.computeFee(standardKey), FEE_500); // pair fee wins

    vm.prank(feeSetter);
    policy.clearPairFee(standardKey.currency0, standardKey.currency1);

    assertEq(policy.pairFees(_pairHash()), 0); // storage deleted
    // Falls through to multiplier: 3000 * 100_000 / 1_000_000 = 300
    assertEq(policy.computeFee(standardKey), FEE_300);
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
    policy.setFeeBuckets(_singleBucketSlope(TEST_BETA_PIPS));
    policy.setDefaultFee(FEE_100);
    policy.setHookFamily(customHook, 1);
    policy.setFamilyDefault(1, FEE_200);
    policy.setPairFee(customKey.currency0, customKey.currency1, FEE_300);
    policy.setFamilyMultiplier(1, 1_000_000); // 1x
    vm.stopPrank();

    // StandardKey -> StaticNativeMath -> pair fee overrides multiplier -> FEE_300
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
    policy.setFeeBuckets(_singleBucketSlope(TEST_BETA_PIPS));

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
    policy.setFeeBuckets(_singleBucketSlope(TEST_BETA_PIPS));

    assertEq(adapter.getFee(standardKey), FEE_300);

    // Deploy new policy with no multiplier configured (default 0)
    vm.startPrank(owner);
    V4FeePolicy newPolicy = new V4FeePolicy(IPoolManager(address(poolManager)));
    newPolicy.setFeeSetter(feeSetter);
    adapter.setPolicy(newPolicy);
    vm.stopPrank();

    // New policy has multiplier == 0 -> 0
    assertEq(adapter.getFee(standardKey), 0);
  }

  // ============ Policy: Flag Rules Configuration ============

  function test_setFlagRules_success() public {
    FlagRule[] memory rules = new FlagRule[](2);
    rules[0] = FlagRule({
      requiredFlags: HookFeeFlags.STABLE_PAIR | HookFeeFlags.TAKES_SWAP_SURPLUS, familyId: 3
    });
    rules[1] = FlagRule({requiredFlags: HookFeeFlags.TAKES_SWAP_SURPLUS, familyId: 2});

    vm.expectEmit(false, false, false, true, address(policy));
    emit IV4FeePolicy.FlagRulesUpdated(2);
    vm.prank(feeSetter);
    policy.setFlagRules(rules);
    vm.snapshotGasLastCall("policy.setFlagRules - two rules");

    assertEq(policy.flagRulesLength(), 2);
    (uint256 flags0, uint8 fam0) = policy.flagRules(0);
    assertEq(flags0, HookFeeFlags.STABLE_PAIR | HookFeeFlags.TAKES_SWAP_SURPLUS);
    assertEq(fam0, 3);
    (uint256 flags1, uint8 fam1) = policy.flagRules(1);
    assertEq(flags1, HookFeeFlags.TAKES_SWAP_SURPLUS);
    assertEq(fam1, 2);
  }

  function test_setFlagRules_replacesExisting() public {
    FlagRule[] memory rules1 = new FlagRule[](2);
    rules1[0] = FlagRule({requiredFlags: HookFeeFlags.STABLE_PAIR, familyId: 1});
    rules1[1] = FlagRule({requiredFlags: HookFeeFlags.TAKES_SWAP_SURPLUS, familyId: 2});

    FlagRule[] memory rules2 = new FlagRule[](1);
    rules2[0] = FlagRule({requiredFlags: HookFeeFlags.ORACLE_BASED, familyId: 5});

    vm.startPrank(feeSetter);
    policy.setFlagRules(rules1);
    assertEq(policy.flagRulesLength(), 2);
    policy.setFlagRules(rules2);
    assertEq(policy.flagRulesLength(), 1);
    vm.stopPrank();

    (uint256 flags, uint8 fam) = policy.flagRules(0);
    assertEq(flags, HookFeeFlags.ORACLE_BASED);
    assertEq(fam, 5);
  }

  function test_setFlagRules_revertsUnauthorized() public {
    FlagRule[] memory rules = new FlagRule[](1);
    rules[0] = FlagRule({requiredFlags: HookFeeFlags.STABLE_PAIR, familyId: 1});
    vm.prank(alice);
    vm.expectRevert(IV4FeePolicy.Unauthorized.selector);
    policy.setFlagRules(rules);
  }

  function test_setFlagRules_revertsZeroRequiredFlags() public {
    FlagRule[] memory rules = new FlagRule[](1);
    rules[0] = FlagRule({requiredFlags: 0, familyId: 1});
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.InvalidFlagRule.selector);
    policy.setFlagRules(rules);
  }

  function test_setFlagRules_revertsZeroFamilyId() public {
    FlagRule[] memory rules = new FlagRule[](1);
    rules[0] = FlagRule({requiredFlags: HookFeeFlags.STABLE_PAIR, familyId: 0});
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.InvalidFlagRule.selector);
    policy.setFlagRules(rules);
  }

  function test_setFlagRules_revertsTooManyRules() public {
    FlagRule[] memory rules = new FlagRule[](33);
    for (uint256 i; i < 33; ++i) {
      rules[i] = FlagRule({requiredFlags: 1 << i, familyId: uint8(i + 1)});
    }
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.TooManyFlagRules.selector);
    policy.setFlagRules(rules);
  }

  function test_clearFlagRules() public {
    FlagRule[] memory rules = new FlagRule[](1);
    rules[0] = FlagRule({requiredFlags: HookFeeFlags.STABLE_PAIR, familyId: 1});
    vm.startPrank(feeSetter);
    policy.setFlagRules(rules);
    assertEq(policy.flagRulesLength(), 1);

    vm.expectEmit(false, false, false, true, address(policy));
    emit IV4FeePolicy.FlagRulesUpdated(0);
    policy.clearFlagRules();
    assertEq(policy.flagRulesLength(), 0);
    vm.stopPrank();
  }

  function test_clearFlagRules_revertsUnauthorized() public {
    vm.prank(alice);
    vm.expectRevert(IV4FeePolicy.Unauthorized.selector);
    policy.clearFlagRules();
  }

  // ============ Policy: Flag-Based Classification ============

  function test_flagRule_singleFlagMatch() public {
    uint160 addrFlags = (1 << 7) | (1 << 2); // custom accounting
    address hookAddr = address(addrFlags);
    uint256 feeFlags = HookFeeFlags.TAKES_SWAP_SURPLUS;
    MockFeeClassifiedHook impl = new MockFeeClassifiedHook(feeFlags);
    vm.etch(hookAddr, address(impl).code);

    PoolKey memory key = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(hookAddr)
    });
    poolManager.mockInitialize(key);

    FlagRule[] memory rules = new FlagRule[](1);
    rules[0] = FlagRule({requiredFlags: HookFeeFlags.TAKES_SWAP_SURPLUS, familyId: 2});

    vm.startPrank(feeSetter);
    policy.setFlagRules(rules);
    policy.setFamilyDefault(2, FEE_300);
    vm.stopPrank();

    assertEq(policy.computeFee(key), FEE_300);
    vm.snapshotGasLastCall("policy.computeFee - flag-rule single flag match");
  }

  function test_flagRule_multiFlagMatch() public {
    uint160 addrFlags = (1 << 7) | (1 << 2);
    address hookAddr = address(addrFlags);
    uint256 feeFlags = HookFeeFlags.TAKES_SWAP_SURPLUS | HookFeeFlags.STABLE_PAIR;
    MockFeeClassifiedHook impl = new MockFeeClassifiedHook(feeFlags);
    vm.etch(hookAddr, address(impl).code);

    PoolKey memory key = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(hookAddr)
    });
    poolManager.mockInitialize(key);

    FlagRule[] memory rules = new FlagRule[](2);
    // More specific rule first: both flags required
    rules[0] = FlagRule({
      requiredFlags: HookFeeFlags.STABLE_PAIR | HookFeeFlags.TAKES_SWAP_SURPLUS, familyId: 3
    });
    // Less specific: only one flag
    rules[1] = FlagRule({requiredFlags: HookFeeFlags.TAKES_SWAP_SURPLUS, familyId: 2});

    vm.startPrank(feeSetter);
    policy.setFlagRules(rules);
    policy.setFamilyDefault(2, FEE_200);
    policy.setFamilyDefault(3, FEE_500);
    vm.stopPrank();

    // Hook has both flags -> matches rule 0 (family 3) first
    assertEq(policy.computeFee(key), FEE_500);
    vm.snapshotGasLastCall("policy.computeFee - flag-rule multi-flag match");
  }

  function test_flagRule_priorityOrdering() public {
    uint160 addrFlags = (1 << 7) | (1 << 2);
    address hookAddr = address(addrFlags);
    // Hook only has TAKES_SWAP_SURPLUS (not STABLE_PAIR)
    uint256 feeFlags = HookFeeFlags.TAKES_SWAP_SURPLUS;
    MockFeeClassifiedHook impl = new MockFeeClassifiedHook(feeFlags);
    vm.etch(hookAddr, address(impl).code);

    PoolKey memory key = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(hookAddr)
    });
    poolManager.mockInitialize(key);

    FlagRule[] memory rules = new FlagRule[](2);
    rules[0] = FlagRule({
      requiredFlags: HookFeeFlags.STABLE_PAIR | HookFeeFlags.TAKES_SWAP_SURPLUS, familyId: 3
    });
    rules[1] = FlagRule({requiredFlags: HookFeeFlags.TAKES_SWAP_SURPLUS, familyId: 2});

    vm.startPrank(feeSetter);
    policy.setFlagRules(rules);
    policy.setFamilyDefault(2, FEE_200);
    policy.setFamilyDefault(3, FEE_500);
    vm.stopPrank();

    // Hook lacks STABLE_PAIR -> skips rule 0, matches rule 1 (family 2)
    assertEq(policy.computeFee(key), FEE_200);
  }

  function test_flagRule_noMatchFallsToDefault() public {
    uint160 addrFlags = (1 << 7) | (1 << 2);
    address hookAddr = address(addrFlags);
    // Hook reports ORACLE_BASED but no rules match that
    uint256 feeFlags = HookFeeFlags.ORACLE_BASED;
    MockFeeClassifiedHook impl = new MockFeeClassifiedHook(feeFlags);
    vm.etch(hookAddr, address(impl).code);

    PoolKey memory key = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(hookAddr)
    });
    poolManager.mockInitialize(key);

    FlagRule[] memory rules = new FlagRule[](1);
    rules[0] = FlagRule({requiredFlags: HookFeeFlags.STABLE_PAIR, familyId: 1});

    vm.startPrank(feeSetter);
    policy.setFlagRules(rules);
    policy.setDefaultFee(FEE_100);
    vm.stopPrank();

    // No rule matches ORACLE_BASED -> falls through to defaultFee
    assertEq(policy.computeFee(key), FEE_100);
  }

  function test_flagRule_hookReportsZeroFlagsFallsToDefault() public {
    uint160 addrFlags = (1 << 7) | (1 << 2);
    address hookAddr = address(addrFlags);
    // Hook reports zero flags
    MockFeeClassifiedHook impl = new MockFeeClassifiedHook(0);
    vm.etch(hookAddr, address(impl).code);

    PoolKey memory key = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(hookAddr)
    });
    poolManager.mockInitialize(key);

    FlagRule[] memory rules = new FlagRule[](1);
    rules[0] = FlagRule({requiredFlags: HookFeeFlags.STABLE_PAIR, familyId: 1});

    vm.startPrank(feeSetter);
    policy.setFlagRules(rules);
    policy.setFamilyDefault(1, FEE_500);
    policy.setDefaultFee(FEE_100);
    vm.stopPrank();

    // Zero flags -> skips rule matching entirely -> defaultFee
    assertEq(policy.computeFee(key), FEE_100);
  }

  function test_flagRule_noRulesConfiguredFallsToDefault() public {
    uint160 addrFlags = (1 << 7) | (1 << 2);
    address hookAddr = address(addrFlags);
    uint256 feeFlags = HookFeeFlags.TAKES_SWAP_SURPLUS;
    MockFeeClassifiedHook impl = new MockFeeClassifiedHook(feeFlags);
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

    // No flag rules configured -> skips staticcall entirely -> defaultFee
    assertEq(policy.computeFee(key), FEE_100);
  }

  function test_flagRule_superset_matchesSubsetRule() public {
    uint160 addrFlags = (1 << 7) | (1 << 2);
    address hookAddr = address(addrFlags);
    // Hook reports many flags
    uint256 feeFlags = HookFeeFlags.TAKES_SWAP_SURPLUS | HookFeeFlags.STABLE_PAIR
      | HookFeeFlags.ORACLE_BASED | HookFeeFlags.YIELD_BEARING;
    MockFeeClassifiedHook impl = new MockFeeClassifiedHook(feeFlags);
    vm.etch(hookAddr, address(impl).code);

    PoolKey memory key = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(hookAddr)
    });
    poolManager.mockInitialize(key);

    FlagRule[] memory rules = new FlagRule[](1);
    // Rule only requires STABLE_PAIR
    rules[0] = FlagRule({requiredFlags: HookFeeFlags.STABLE_PAIR, familyId: 4});

    vm.startPrank(feeSetter);
    policy.setFlagRules(rules);
    policy.setFamilyDefault(4, FEE_200);
    vm.stopPrank();

    // Hook has STABLE_PAIR among other flags -> matches
    assertEq(policy.computeFee(key), FEE_200);
  }

  function test_flagRule_withPairFeeAndMultiplier() public {
    uint160 addrFlags = (1 << 7) | (1 << 2);
    address hookAddr = address(addrFlags);
    uint256 feeFlags = HookFeeFlags.STABLE_PAIR | HookFeeFlags.TAKES_SWAP_SURPLUS;
    MockFeeClassifiedHook impl = new MockFeeClassifiedHook(feeFlags);
    vm.etch(hookAddr, address(impl).code);

    PoolKey memory key = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(hookAddr)
    });
    poolManager.mockInitialize(key);

    FlagRule[] memory rules = new FlagRule[](1);
    rules[0] = FlagRule({
      requiredFlags: HookFeeFlags.STABLE_PAIR | HookFeeFlags.TAKES_SWAP_SURPLUS, familyId: 3
    });

    vm.startPrank(feeSetter);
    policy.setFlagRules(rules);
    policy.setPairFee(key.currency0, key.currency1, FEE_200);
    policy.setFamilyMultiplier(3, 500_000); // 50%
    vm.stopPrank();

    // FEE_200 (200|200) * 50% = (100|100) = FEE_100
    assertEq(policy.computeFee(key), FEE_100);
  }

  function test_flagRule_governanceOverrideTakesPriorityOverFlags() public {
    uint160 addrFlags = (1 << 7) | (1 << 2);
    address hookAddr = address(addrFlags);
    uint256 feeFlags = HookFeeFlags.TAKES_SWAP_SURPLUS;
    MockFeeClassifiedHook impl = new MockFeeClassifiedHook(feeFlags);
    vm.etch(hookAddr, address(impl).code);

    PoolKey memory key = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(hookAddr)
    });
    poolManager.mockInitialize(key);

    FlagRule[] memory rules = new FlagRule[](1);
    rules[0] = FlagRule({requiredFlags: HookFeeFlags.TAKES_SWAP_SURPLUS, familyId: 2});

    vm.startPrank(feeSetter);
    policy.setFlagRules(rules);
    policy.setFamilyDefault(2, FEE_200); // flag-rule would give this
    policy.setHookFamily(hookAddr, 5); // governance override
    policy.setFamilyDefault(5, FEE_500); // governance family fee
    vm.stopPrank();

    // Governance override (family 5) wins over flag-rule match (family 2)
    assertEq(policy.computeFee(key), FEE_500);
  }

  function test_flagRule_max32Rules() public {
    FlagRule[] memory rules = new FlagRule[](32);
    for (uint256 i; i < 32; ++i) {
      rules[i] = FlagRule({requiredFlags: 1 << i, familyId: uint8(i + 1)});
    }
    vm.prank(feeSetter);
    policy.setFlagRules(rules);
    vm.snapshotGasLastCall("policy.setFlagRules - 32 rules (max)");
    assertEq(policy.flagRulesLength(), 32);
  }
}
