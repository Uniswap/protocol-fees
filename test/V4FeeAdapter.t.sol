// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ProtocolFeesTestBase} from "./utils/ProtocolFeesTestBase.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {MockPoolManager} from "./mocks/MockPoolManager.sol";
import {V4FeeAdapter, IV4FeeAdapter} from "../src/feeAdapters/V4FeeAdapter.sol";

contract V4FeeAdapterTest is ProtocolFeesTestBase {
  using PoolIdLibrary for PoolKey;

  MockPoolManager public poolManager;
  V4FeeAdapter public feeAdapter;

  // Common fee values for testing (single-direction pips)
  // V4 protocol fees are in pips (1/1_000_000), max 1000 per direction
  // The adapter stores single-direction values and packs them symmetrically on retrieval
  uint24 constant DEFAULT_FEE = 500; // 0.05%
  uint24 constant TIER_FEE_3000 = 300; // 0.03%
  uint24 constant TIER_FEE_500 = 200; // 0.02%
  uint24 constant POOL_OVERRIDE_FEE = 100; // 0.01%
  uint24 constant MAX_VALID_FEE = 1000; // Max valid per direction: 0.1%

  /// @notice Packs a single-direction fee into both directions (matches V4FeeAdapter._packFee)
  function _packFee(uint24 fee) internal pure returns (uint24) {
    return (fee << 12) | fee;
  }

  // Test pool keys
  PoolKey pool3000;
  PoolKey pool500;
  PoolKey poolCustom;

  function setUp() public override {
    super.setUp();

    // Deploy mock pool manager with owner as the owner
    vm.startPrank(owner);
    poolManager = new MockPoolManager(owner);

    // Deploy fee adapter with no default (0 = not set)
    feeAdapter = new V4FeeAdapter(
      address(poolManager),
      address(tokenJar),
      owner, // feeSetter
      0 // no default initially
    );

    // Set fee adapter as the protocol fee controller
    poolManager.setProtocolFeeController(address(feeAdapter));
    vm.stopPrank();

    // Create test pool keys with different LP fee tiers
    pool3000 = PoolKey({
      currency0: Currency.wrap(address(mockToken)),
      currency1: Currency.wrap(address(mockToken1)),
      fee: 3000, // 0.30% LP fee
      tickSpacing: 60,
      hooks: IHooks(address(0))
    });

    pool500 = PoolKey({
      currency0: Currency.wrap(address(mockToken)),
      currency1: Currency.wrap(address(mockToken1)),
      fee: 500, // 0.05% LP fee
      tickSpacing: 10,
      hooks: IHooks(address(0))
    });

    poolCustom = PoolKey({
      currency0: Currency.wrap(address(mockToken)),
      currency1: Currency.wrap(address(mockToken1)),
      fee: 10000, // 1% LP fee
      tickSpacing: 200,
      hooks: IHooks(address(0))
    });

    // Initialize pools in mock manager
    poolManager.mockInitialize(pool3000);
    poolManager.mockInitialize(pool500);
    poolManager.mockInitialize(poolCustom);
  }

  // ═══════════════════════════════════════════════════════════════
  //                      CONSTRUCTOR TESTS
  // ═══════════════════════════════════════════════════════════════

  function test_constructor_setsPoolManager() public view {
    assertEq(address(feeAdapter.POOL_MANAGER()), address(poolManager));
  }

  function test_constructor_setsTokenJar() public view {
    assertEq(feeAdapter.TOKEN_JAR(), address(tokenJar));
  }

  function test_constructor_setsFeeSetter() public view {
    assertEq(feeAdapter.feeSetter(), owner);
  }

  function test_constructor_setsDefaultFee() public view {
    assertEq(feeAdapter.defaultFee(), 0); // 0 = not set
  }

  function test_constructor_revertsWithInvalidDefaultFee() public {
    uint24 invalidFee = 2000; // > MAX_PROTOCOL_FEE
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(IV4FeeAdapter.ProtocolFeeTooLarge.selector, invalidFee));
    new V4FeeAdapter(address(poolManager), address(tokenJar), owner, invalidFee);
  }

  function test_constructor_acceptsZeroDefault() public {
    vm.prank(owner);
    V4FeeAdapter adapter = new V4FeeAdapter(address(poolManager), address(tokenJar), owner, 0);
    assertEq(adapter.defaultFee(), 0);
  }

  // ═══════════════════════════════════════════════════════════════
  //                    WATERFALL RESOLUTION TESTS
  // ═══════════════════════════════════════════════════════════════

  function test_getFee_returnsZero_whenNothingSet() public view {
    // Nothing configured, should return 0
    assertEq(feeAdapter.getFee(pool3000), 0);
  }

  function test_getFee_returnsDefault_whenOnlyDefaultSet() public {
    vm.prank(owner);
    feeAdapter.setDefaultFee(DEFAULT_FEE);

    assertEq(feeAdapter.getFee(pool3000), _packFee(DEFAULT_FEE));
    assertEq(feeAdapter.getFee(pool500), _packFee(DEFAULT_FEE));
    assertEq(feeAdapter.getFee(poolCustom), _packFee(DEFAULT_FEE));
  }

  function test_getFee_returnsFeeTier_overDefault() public {
    vm.startPrank(owner);
    feeAdapter.setDefaultFee(DEFAULT_FEE);
    feeAdapter.setFeeTierOverride(3000, TIER_FEE_3000);
    vm.stopPrank();

    // pool3000 should use tier override
    assertEq(feeAdapter.getFee(pool3000), _packFee(TIER_FEE_3000));
    // pool500 should fall through to default
    assertEq(feeAdapter.getFee(pool500), _packFee(DEFAULT_FEE));
  }

  function test_getFee_returnsPoolOverride_overFeeTier() public {
    vm.startPrank(owner);
    feeAdapter.setDefaultFee(DEFAULT_FEE);
    feeAdapter.setFeeTierOverride(3000, TIER_FEE_3000);
    feeAdapter.setPoolOverride(pool3000.toId(), POOL_OVERRIDE_FEE);
    vm.stopPrank();

    // pool3000 should use pool override (highest priority)
    assertEq(feeAdapter.getFee(pool3000), _packFee(POOL_OVERRIDE_FEE));
    // pool500 should fall through to default
    assertEq(feeAdapter.getFee(pool500), _packFee(DEFAULT_FEE));
  }

  function test_getFee_fullWaterfall() public {
    vm.startPrank(owner);
    // Set all levels
    feeAdapter.setDefaultFee(DEFAULT_FEE);
    feeAdapter.setFeeTierOverride(3000, TIER_FEE_3000);
    feeAdapter.setFeeTierOverride(500, TIER_FEE_500);
    feeAdapter.setPoolOverride(pool3000.toId(), POOL_OVERRIDE_FEE);
    vm.stopPrank();

    // pool3000: has pool override → uses pool override
    assertEq(feeAdapter.getFee(pool3000), _packFee(POOL_OVERRIDE_FEE));
    // pool500: has tier override, no pool override → uses tier override
    assertEq(feeAdapter.getFee(pool500), _packFee(TIER_FEE_500));
    // poolCustom: no pool or tier override → uses default
    assertEq(feeAdapter.getFee(poolCustom), _packFee(DEFAULT_FEE));
  }

  function test_getFee_poolOverrideZero_disablesFee() public {
    vm.startPrank(owner);
    feeAdapter.setDefaultFee(DEFAULT_FEE);
    feeAdapter.setFeeTierOverride(3000, TIER_FEE_3000);
    // Explicitly set pool override to 0 (disabled)
    feeAdapter.setPoolOverride(pool3000.toId(), 0);
    vm.stopPrank();

    // pool3000 should use pool override of 0 (fees disabled)
    assertEq(feeAdapter.getFee(pool3000), 0);
  }

  function test_getFee_feeTierZero_disablesFee() public {
    vm.startPrank(owner);
    feeAdapter.setDefaultFee(DEFAULT_FEE);
    // Explicitly set tier override to 0
    feeAdapter.setFeeTierOverride(3000, 0);
    vm.stopPrank();

    // pool3000 should use tier override of 0 (no packing for zero)
    assertEq(feeAdapter.getFee(pool3000), 0);
    // pool500 should fall through to default
    assertEq(feeAdapter.getFee(pool500), _packFee(DEFAULT_FEE));
  }

  // ═══════════════════════════════════════════════════════════════
  //                      APPLY FEE TESTS
  // ═══════════════════════════════════════════════════════════════

  function test_applyFee_setsProtocolFeeOnPoolManager() public {
    vm.prank(owner);
    feeAdapter.setDefaultFee(DEFAULT_FEE);

    feeAdapter.applyFee(pool3000);

    assertEq(poolManager.getProtocolFee(pool3000.toId()), _packFee(DEFAULT_FEE));
  }

  function test_applyFee_respectsWaterfall() public {
    vm.startPrank(owner);
    feeAdapter.setDefaultFee(DEFAULT_FEE);
    feeAdapter.setFeeTierOverride(3000, TIER_FEE_3000);
    feeAdapter.setPoolOverride(pool500.toId(), POOL_OVERRIDE_FEE);
    vm.stopPrank();

    feeAdapter.applyFee(pool3000);
    feeAdapter.applyFee(pool500);
    feeAdapter.applyFee(poolCustom);

    assertEq(poolManager.getProtocolFee(pool3000.toId()), _packFee(TIER_FEE_3000));
    assertEq(poolManager.getProtocolFee(pool500.toId()), _packFee(POOL_OVERRIDE_FEE));
    assertEq(poolManager.getProtocolFee(poolCustom.toId()), _packFee(DEFAULT_FEE));
  }

  function test_batchApplyFees_setsMultiplePoolFees() public {
    vm.startPrank(owner);
    feeAdapter.setDefaultFee(DEFAULT_FEE);
    feeAdapter.setFeeTierOverride(3000, TIER_FEE_3000);
    feeAdapter.setPoolOverride(pool500.toId(), POOL_OVERRIDE_FEE);
    vm.stopPrank();

    PoolKey[] memory keys = new PoolKey[](3);
    keys[0] = pool3000;
    keys[1] = pool500;
    keys[2] = poolCustom;

    feeAdapter.batchApplyFees(keys);

    assertEq(poolManager.getProtocolFee(pool3000.toId()), _packFee(TIER_FEE_3000));
    assertEq(poolManager.getProtocolFee(pool500.toId()), _packFee(POOL_OVERRIDE_FEE));
    assertEq(poolManager.getProtocolFee(poolCustom.toId()), _packFee(DEFAULT_FEE));
  }

  // ═══════════════════════════════════════════════════════════════
  //                    CLEAR OVERRIDE TESTS
  // ═══════════════════════════════════════════════════════════════

  function test_clearPoolOverride_fallsBackToTier() public {
    vm.startPrank(owner);
    feeAdapter.setDefaultFee(DEFAULT_FEE);
    feeAdapter.setFeeTierOverride(3000, TIER_FEE_3000);
    feeAdapter.setPoolOverride(pool3000.toId(), POOL_OVERRIDE_FEE);

    // Verify pool override is active
    assertEq(feeAdapter.getFee(pool3000), _packFee(POOL_OVERRIDE_FEE));

    // Clear pool override
    feeAdapter.clearPoolOverride(pool3000.toId());
    vm.stopPrank();

    // Should now fall back to tier override
    assertEq(feeAdapter.getFee(pool3000), _packFee(TIER_FEE_3000));
  }

  function test_clearFeeTierOverride_fallsBackToDefault() public {
    vm.startPrank(owner);
    feeAdapter.setDefaultFee(DEFAULT_FEE);
    feeAdapter.setFeeTierOverride(3000, TIER_FEE_3000);

    // Verify tier override is active
    assertEq(feeAdapter.getFee(pool3000), _packFee(TIER_FEE_3000));

    // Clear tier override
    feeAdapter.clearFeeTierOverride(3000);
    vm.stopPrank();

    // Should now fall back to default
    assertEq(feeAdapter.getFee(pool3000), _packFee(DEFAULT_FEE));
  }

  function test_clearOverride_emitsEvent() public {
    vm.startPrank(owner);
    feeAdapter.setPoolOverride(pool3000.toId(), POOL_OVERRIDE_FEE);

    vm.expectEmit(true, false, false, true);
    emit IV4FeeAdapter.PoolOverrideUpdated(pool3000.toId(), 0); // 0 = cleared
    feeAdapter.clearPoolOverride(pool3000.toId());
    vm.stopPrank();
  }

  // ═══════════════════════════════════════════════════════════════
  //                    ACCESS CONTROL TESTS
  // ═══════════════════════════════════════════════════════════════

  function test_setDefaultFee_onlyFeeSetter() public {
    vm.prank(alice);
    vm.expectRevert(IV4FeeAdapter.Unauthorized.selector);
    feeAdapter.setDefaultFee(DEFAULT_FEE);
  }

  function test_setFeeTierOverride_onlyFeeSetter() public {
    vm.prank(alice);
    vm.expectRevert(IV4FeeAdapter.Unauthorized.selector);
    feeAdapter.setFeeTierOverride(3000, TIER_FEE_3000);
  }

  function test_setPoolOverride_onlyFeeSetter() public {
    vm.prank(alice);
    vm.expectRevert(IV4FeeAdapter.Unauthorized.selector);
    feeAdapter.setPoolOverride(pool3000.toId(), POOL_OVERRIDE_FEE);
  }

  function test_clearFeeTierOverride_onlyFeeSetter() public {
    vm.prank(alice);
    vm.expectRevert(IV4FeeAdapter.Unauthorized.selector);
    feeAdapter.clearFeeTierOverride(3000);
  }

  function test_clearPoolOverride_onlyFeeSetter() public {
    vm.prank(alice);
    vm.expectRevert(IV4FeeAdapter.Unauthorized.selector);
    feeAdapter.clearPoolOverride(pool3000.toId());
  }

  function test_setFeeSetter_onlyOwner() public {
    vm.prank(alice);
    vm.expectRevert("UNAUTHORIZED");
    feeAdapter.setFeeSetter(alice);
  }

  function test_setFeeSetter_success() public {
    vm.prank(owner);
    feeAdapter.setFeeSetter(alice);

    assertEq(feeAdapter.feeSetter(), alice);

    // Alice can now set fees
    vm.prank(alice);
    feeAdapter.setDefaultFee(DEFAULT_FEE);
    assertEq(feeAdapter.defaultFee(), DEFAULT_FEE);
  }

  function test_collectProtocolFees_onlyOwner() public {
    vm.prank(alice);
    vm.expectRevert("UNAUTHORIZED");
    feeAdapter.collectProtocolFees(Currency.wrap(address(mockToken)), 0);
  }

  // ═══════════════════════════════════════════════════════════════
  //                    FEE VALIDATION TESTS
  // ═══════════════════════════════════════════════════════════════

  function test_setDefaultFee_revertsWithInvalidFee() public {
    uint24 invalidFee = 2000; // > MAX_PROTOCOL_FEE (1000)
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(IV4FeeAdapter.ProtocolFeeTooLarge.selector, invalidFee));
    feeAdapter.setDefaultFee(invalidFee);
  }

  function test_setFeeTierOverride_revertsWithInvalidFee() public {
    uint24 invalidFee = 1001; // Just over max
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(IV4FeeAdapter.ProtocolFeeTooLarge.selector, invalidFee));
    feeAdapter.setFeeTierOverride(3000, invalidFee);
  }

  function test_setPoolOverride_revertsWithInvalidFee() public {
    uint24 invalidFee = 1001; // Just over max (single direction)
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(IV4FeeAdapter.ProtocolFeeTooLarge.selector, invalidFee));
    feeAdapter.setPoolOverride(pool3000.toId(), invalidFee);
  }

  function test_setFee_acceptsMaxValidFee() public {
    vm.prank(owner);
    feeAdapter.setDefaultFee(MAX_VALID_FEE); // 1000 pips (0.1%)
    assertEq(feeAdapter.defaultFee(), MAX_VALID_FEE);
    assertEq(feeAdapter.getFee(pool3000), _packFee(MAX_VALID_FEE));
  }

  function test_setFee_acceptsZeroFee() public {
    vm.prank(owner);
    feeAdapter.setDefaultFee(0);
    // Storage is encoded: 0 becomes ZERO_FEE_SENTINEL
    assertEq(feeAdapter.defaultFee(), feeAdapter.ZERO_FEE_SENTINEL());
    // But getFee should decode it back to 0
    assertEq(feeAdapter.getFee(pool3000), 0);
  }

  // ═══════════════════════════════════════════════════════════════
  //                       EVENT TESTS
  // ═══════════════════════════════════════════════════════════════

  function test_setDefaultFee_emitsEvent() public {
    vm.prank(owner);
    vm.expectEmit(false, false, false, true);
    emit IV4FeeAdapter.DefaultFeeUpdated(DEFAULT_FEE);
    feeAdapter.setDefaultFee(DEFAULT_FEE);
  }

  function test_setFeeTierOverride_emitsEvent() public {
    vm.prank(owner);
    vm.expectEmit(true, false, false, true);
    emit IV4FeeAdapter.FeeTierOverrideUpdated(3000, TIER_FEE_3000);
    feeAdapter.setFeeTierOverride(3000, TIER_FEE_3000);
  }

  function test_setPoolOverride_emitsEvent() public {
    vm.prank(owner);
    vm.expectEmit(true, false, false, true);
    emit IV4FeeAdapter.PoolOverrideUpdated(pool3000.toId(), POOL_OVERRIDE_FEE);
    feeAdapter.setPoolOverride(pool3000.toId(), POOL_OVERRIDE_FEE);
  }

  function test_setFeeSetter_emitsEvent() public {
    vm.prank(owner);
    vm.expectEmit(true, false, false, false);
    emit IV4FeeAdapter.FeeSetterUpdated(alice);
    feeAdapter.setFeeSetter(alice);
  }

  // ═══════════════════════════════════════════════════════════════
  //                    FEE COLLECTION TESTS
  // ═══════════════════════════════════════════════════════════════

  function test_collectProtocolFees_success() public {
    // Setup: accrue some fees in the pool manager
    uint256 accruedAmount = 100e18;
    poolManager.setProtocolFeesAccrued(Currency.wrap(address(mockToken)), accruedAmount);

    // Fund the pool manager so it can transfer
    mockToken.mint(address(poolManager), accruedAmount);

    uint256 tokenJarBalanceBefore = mockToken.balanceOf(address(tokenJar));

    vm.prank(owner);
    uint256 collected = feeAdapter.collectProtocolFees(Currency.wrap(address(mockToken)), accruedAmount);

    assertEq(collected, accruedAmount);
    assertEq(mockToken.balanceOf(address(tokenJar)), tokenJarBalanceBefore + accruedAmount);
  }

  // ═══════════════════════════════════════════════════════════════
  //                        FUZZ TESTS
  // ═══════════════════════════════════════════════════════════════

  function testFuzz_setDefaultFee(uint24 fee) public {
    vm.startPrank(owner);

    // 0 is valid (explicitly disabled), otherwise must be <= MAX_PROTOCOL_FEE (1000)
    if (fee != 0 && fee > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) {
      vm.expectRevert(abi.encodeWithSelector(IV4FeeAdapter.ProtocolFeeTooLarge.selector, fee));
      feeAdapter.setDefaultFee(fee);
    } else {
      feeAdapter.setDefaultFee(fee);
      // Storage is encoded: 0 becomes ZERO_FEE_SENTINEL
      uint24 expectedStored = fee == 0 ? feeAdapter.ZERO_FEE_SENTINEL() : fee;
      assertEq(feeAdapter.defaultFee(), expectedStored);
    }

    vm.stopPrank();
  }

  function testFuzz_setFeeTierOverride(uint24 lpFee, uint24 protocolFee) public {
    vm.startPrank(owner);

    if (protocolFee != 0 && protocolFee > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) {
      vm.expectRevert(abi.encodeWithSelector(IV4FeeAdapter.ProtocolFeeTooLarge.selector, protocolFee));
      feeAdapter.setFeeTierOverride(lpFee, protocolFee);
    } else {
      feeAdapter.setFeeTierOverride(lpFee, protocolFee);
      // Storage is encoded: 0 becomes ZERO_FEE_SENTINEL
      uint24 expectedStored = protocolFee == 0 ? feeAdapter.ZERO_FEE_SENTINEL() : protocolFee;
      assertEq(feeAdapter.feeTierOverrides(lpFee), expectedStored);
    }

    vm.stopPrank();
  }

  function testFuzz_setPoolOverride(bytes32 poolIdRaw, uint24 protocolFee) public {
    PoolId poolId = PoolId.wrap(poolIdRaw);

    vm.startPrank(owner);

    if (protocolFee != 0 && protocolFee > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) {
      vm.expectRevert(abi.encodeWithSelector(IV4FeeAdapter.ProtocolFeeTooLarge.selector, protocolFee));
      feeAdapter.setPoolOverride(poolId, protocolFee);
    } else {
      feeAdapter.setPoolOverride(poolId, protocolFee);
      // Storage is encoded: 0 becomes ZERO_FEE_SENTINEL
      uint24 expectedStored = protocolFee == 0 ? feeAdapter.ZERO_FEE_SENTINEL() : protocolFee;
      assertEq(feeAdapter.poolOverrides(poolId), expectedStored);
    }

    vm.stopPrank();
  }

  function testFuzz_setFeeSetter(address newFeeSetter) public {
    vm.prank(owner);
    feeAdapter.setFeeSetter(newFeeSetter);
    assertEq(feeAdapter.feeSetter(), newFeeSetter);
  }

  function testFuzz_onlyFeeSetterCanSetFees(address caller) public {
    vm.assume(caller != owner); // owner is the feeSetter

    vm.prank(caller);
    vm.expectRevert(IV4FeeAdapter.Unauthorized.selector);
    feeAdapter.setDefaultFee(DEFAULT_FEE);
  }

  // ═══════════════════════════════════════════════════════════════
  //                    WATERFALL PRIORITY TESTS
  // ═══════════════════════════════════════════════════════════════

  function test_waterfall_poolOverrideHasHighestPriority() public {
    vm.startPrank(owner);
    // Set all three levels to different values
    feeAdapter.setDefaultFee(100);
    feeAdapter.setFeeTierOverride(3000, 200);
    feeAdapter.setPoolOverride(pool3000.toId(), 300);
    vm.stopPrank();

    // Pool override should win
    assertEq(feeAdapter.getFee(pool3000), _packFee(300));
  }

  function test_waterfall_feeTierHasSecondPriority() public {
    vm.startPrank(owner);
    // Set default and tier (no pool override)
    feeAdapter.setDefaultFee(100);
    feeAdapter.setFeeTierOverride(3000, 200);
    vm.stopPrank();

    // Fee tier should win over default
    assertEq(feeAdapter.getFee(pool3000), _packFee(200));
  }

  function test_waterfall_defaultIsLastResort() public {
    vm.startPrank(owner);
    // Only set default
    feeAdapter.setDefaultFee(100);
    vm.stopPrank();

    // Default should be used
    assertEq(feeAdapter.getFee(pool3000), _packFee(100));
  }

  function test_waterfall_zeroIsValidOverride() public {
    vm.startPrank(owner);
    feeAdapter.setDefaultFee(500);
    feeAdapter.setFeeTierOverride(3000, 300);
    // Set pool override to 0 (explicitly disable fees for this pool)
    feeAdapter.setPoolOverride(pool3000.toId(), 0);
    vm.stopPrank();

    // Zero should be returned (not fall through to tier/default, no packing for zero)
    assertEq(feeAdapter.getFee(pool3000), 0);
  }
}
