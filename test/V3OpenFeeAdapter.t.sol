// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {ProtocolFeesTestBase} from "./utils/ProtocolFeesTestBase.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {
  UniswapV3FactoryDeployer,
  IUniswapV3Factory
} from "briefcase/deployers/v3-core/UniswapV3FactoryDeployer.sol";
import {V3OpenFeeAdapter, IV3OpenFeeAdapter} from "../src/feeAdapters/V3OpenFeeAdapter.sol";
import {IOwned} from "../src/interfaces/base/IOwned.sol";
import {Vm} from "forge-std/Vm.sol";

contract V3OpenFeeAdapterTest is ProtocolFeesTestBase {
  IUniswapV3Factory public factory;

  IV3OpenFeeAdapter public feeAdapter;

  uint160 public constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

  address pool;
  address pool1;

  uint256 slot = 3;

  address feeSetter;

  struct ProtocolFees {
    uint128 token0;
    uint128 token1;
  }

  struct PoolObject {
    address pool;
    uint24 fee;
    /// token1 | token0
    uint8 protocolFee;
  }

  PoolObject poolObject0;
  PoolObject poolObject1;

  function setUp() public override {
    super.setUp();

    factory = UniswapV3FactoryDeployer.deploy();
    /// Prank the old owner so we can just use our internal owner.
    vm.prank(factory.owner());
    factory.setOwner(owner);

    vm.startPrank(owner);
    feeAdapter = new V3OpenFeeAdapter(address(factory), address(tokenJar));
    feeAdapter.setFeeSetter(owner);
    factory.setOwner(address(feeAdapter));
    vm.stopPrank();

    /// Store fee tiers.
    feeAdapter.storeFeeTier(500);
    feeAdapter.storeFeeTier(3000);
    feeAdapter.storeFeeTier(10_000);

    feeSetter = feeAdapter.feeSetter();

    // Create pool.
    pool = factory.createPool(address(mockToken), address(mockToken1), 3000);
    pool1 = factory.createPool(address(mockToken), address(mockToken1), 10_000);
    IUniswapV3Pool(pool).initialize(SQRT_PRICE_1_1);
    IUniswapV3Pool(pool1).initialize(SQRT_PRICE_1_1);

    poolObject0 = PoolObject({pool: pool, fee: 3000, protocolFee: 0});
    poolObject1 = PoolObject({pool: pool1, fee: 10_000, protocolFee: 0});

    // Mint tokens.
    mockToken.mint(address(pool), INITIAL_TOKEN_AMOUNT);
    mockToken1.mint(address(pool), INITIAL_TOKEN_AMOUNT);
  }

  // ============ Basic Setup Tests ============

  function test_feeAdapter_isOwner() public view {
    assertEq(address(factory.owner()), address(feeAdapter));
  }

  function test_tokenJar_isSet() public view {
    assertEq(feeAdapter.TOKEN_JAR(), address(tokenJar));
  }

  function test_enableFeeAmount() public {
    uint24 newTier = 750;
    vm.prank(owner);
    feeAdapter.enableFeeAmount(750, 1);

    uint24 _tier = feeAdapter.feeTiers(3);
    assertEq(_tier, newTier);
  }

  // ============ Collection Tests ============

  function test_collect_full_success() public {
    uint128 amount0 = 10e18;
    uint128 amount1 = 11e18;

    address token0 =
      address(mockToken) < address(mockToken1) ? address(mockToken) : address(mockToken1);
    address token1 =
      address(mockToken) < address(mockToken1) ? address(mockToken1) : address(mockToken);

    _mockSetProtocolFees(amount0, amount1);

    IV3OpenFeeAdapter.CollectParams[] memory collectParams =
      new IV3OpenFeeAdapter.CollectParams[](1);
    collectParams[0] = IV3OpenFeeAdapter.CollectParams({
      pool: pool, amount0Requested: amount0, amount1Requested: amount1
    });

    uint256 balanceBefore = MockERC20(token0).balanceOf(address(tokenJar));
    uint256 balanceBefore1 = MockERC20(token1).balanceOf(address(tokenJar));

    // Anyone can call collect.
    IV3OpenFeeAdapter.Collected[] memory collected = feeAdapter.collect(collectParams);

    // Note that 1 wei is left in the pool.
    assertEq(collected[0].amount0Collected, amount0 - 1);
    assertEq(collected[0].amount1Collected, amount1 - 1);

    // ProtocolFees Test Base pre-funds token jar, and poolManager sends more funds to it
    assertEq(MockERC20(token0).balanceOf(address(tokenJar)), balanceBefore + amount0 - 1);
    assertEq(MockERC20(token1).balanceOf(address(tokenJar)), balanceBefore1 + amount1 - 1);
  }

  // ============ Permissionless Access Tests ============

  function test_triggerFeeUpdate_permissionless_success() public {
    uint8 protocolFee = 10 << 4 | 8;

    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, protocolFee);

    // Anyone can trigger update - use a random address
    address randomCaller = makeAddr("randomCaller");
    vm.prank(randomCaller);
    feeAdapter.triggerFeeUpdate(pool);

    assertEq(_getProtocolFees(pool), protocolFee);
  }

  function test_triggerFeeUpdate_multipleCallers_success() public {
    address caller1 = makeAddr("caller1");
    address caller2 = makeAddr("caller2");

    uint8 protocolFee1 = 10 << 4 | 8;
    uint8 protocolFee2 = 9 << 4 | 7;

    // Set initial fee
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, protocolFee1);

    // First caller updates
    vm.prank(caller1);
    feeAdapter.triggerFeeUpdate(pool);
    assertEq(_getProtocolFees(pool), protocolFee1);

    // Change default fee
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, protocolFee2);

    // Second caller updates with new default
    vm.prank(caller2);
    feeAdapter.triggerFeeUpdate(pool);
    assertEq(_getProtocolFees(pool), protocolFee2);
  }

  function test_triggerFeeUpdate_zeroBalanceCaller_success() public {
    address poorCaller = makeAddr("poorCaller");
    assertEq(poorCaller.balance, 0);

    uint8 protocolFee = 10 << 4 | 8;
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, protocolFee);

    vm.prank(poorCaller);
    feeAdapter.triggerFeeUpdate(pool);

    assertEq(_getProtocolFees(pool), protocolFee);
  }

  function testFuzz_triggerFeeUpdate_anyCallerCanCall(address caller) public {
    vm.assume(caller != address(0));
    vm.assume(caller != address(vm));

    uint8 protocolFee = 10 << 4 | 8;
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, protocolFee);

    vm.prank(caller);
    feeAdapter.triggerFeeUpdate(pool);

    assertEq(_getProtocolFees(pool), protocolFee);
  }

  // ============ Pair-based Update Tests ============

  function test_triggerFeeUpdate_byPair_success() public {
    uint8 fee0 = 5;
    uint8 fee1 = 10;
    uint8 protocolFee3000 = fee1 << 4 | fee0;
    uint8 protocolFee10000 = 4 << 4 | 8;

    // Set the default fees
    vm.startPrank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, protocolFee3000);
    feeAdapter.setDefaultFeeByFeeTier(10_000, protocolFee10000);
    vm.stopPrank();

    (address _token0, address _token1) = address(mockToken) < address(mockToken1)
      ? (address(mockToken), address(mockToken1))
      : (address(mockToken1), address(mockToken));

    // Permissionless call
    feeAdapter.triggerFeeUpdate(_token0, _token1);

    // Both pools should be updated
    assertEq(_getProtocolFees(pool), protocolFee3000);
    assertEq(_getProtocolFees(pool1), protocolFee10000);
  }

  // ============ Batch Update Tests ============

  function test_batchTriggerFeeUpdate_success() public {
    // Create additional pools with different tokens
    MockERC20 tokenA = new MockERC20("TokenA", "TKNA", 18);
    MockERC20 tokenB = new MockERC20("TokenB", "TKNB", 18);

    address poolA = factory.createPool(address(tokenA), address(mockToken1), 3000);
    address poolB = factory.createPool(address(tokenB), address(mockToken1), 3000);
    IUniswapV3Pool(poolA).initialize(SQRT_PRICE_1_1);
    IUniswapV3Pool(poolB).initialize(SQRT_PRICE_1_1);

    uint8 protocolFee = 10 << 4 | 8;
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, protocolFee);

    // Create pairs array
    IV3OpenFeeAdapter.Pair[] memory pairs = new IV3OpenFeeAdapter.Pair[](2);
    pairs[0] = _toPair(address(tokenA), address(mockToken1));
    pairs[1] = _toPair(address(tokenB), address(mockToken1));

    // Batch update - permissionless
    address randomCaller = makeAddr("batchCaller");
    vm.prank(randomCaller);
    feeAdapter.batchTriggerFeeUpdate(pairs);

    assertEq(_getProtocolFees(poolA), protocolFee);
    assertEq(_getProtocolFees(poolB), protocolFee);
  }

  function test_batchTriggerFeeUpdateByPool_success() public {
    uint8 protocolFee3000 = 10 << 4 | 8;
    uint8 protocolFee10000 = 9 << 4 | 7;

    vm.startPrank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, protocolFee3000);
    feeAdapter.setDefaultFeeByFeeTier(10_000, protocolFee10000);
    vm.stopPrank();

    address[] memory pools = new address[](2);
    pools[0] = pool;
    pools[1] = pool1;

    // Batch update by pool - permissionless
    address randomCaller = makeAddr("batchCaller");
    vm.prank(randomCaller);
    feeAdapter.batchTriggerFeeUpdateByPool(pools);

    assertEq(_getProtocolFees(pool), protocolFee3000);
    assertEq(_getProtocolFees(pool1), protocolFee10000);
  }

  // ============ Edge Case Tests ============

  function test_triggerFeeUpdate_skipsUninitializedPool() public {
    // Create a new pool but don't initialize it
    MockERC20 token2 = new MockERC20("Token2", "TKN2", 18);
    address uninitializedPool = factory.createPool(address(token2), address(mockToken1), 3000);
    // Note: We don't call IUniswapV3Pool(uninitializedPool).initialize()

    uint8 protocolFee = 10 << 4 | 8;
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, protocolFee);

    // This should not revert - the function should silently skip the uninitialized pool
    feeAdapter.triggerFeeUpdate(uninitializedPool);

    // Verify that the protocol fee was NOT set (pool fee should be 0)
    (,,,,, uint8 poolFees,) = IUniswapV3Pool(uninitializedPool).slot0();
    assertEq(poolFees, 0);

    // Verify that initialized pools still work correctly
    feeAdapter.triggerFeeUpdate(pool);
    assertEq(_getProtocolFees(pool), protocolFee);
  }

  function test_triggerFeeUpdate_skipsNonExistentPool() public {
    uint8 protocolFee = 10 << 4 | 8;
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, protocolFee);

    // Try to update a non-existent pool address (no code)
    address fakePool = makeAddr("fakePool");

    // Should not revert due to extcodesize check
    feeAdapter.triggerFeeUpdate(fakePool);

    // No state change expected (can't really verify, but test passes = no revert)
  }

  function test_triggerFeeUpdate_withoutDefaultFee_setsZero() public {
    // No default fee set for 3000 tier
    assertEq(feeAdapter.defaultFees(3000), 0);

    // Anyone can trigger update
    feeAdapter.triggerFeeUpdate(pool);

    // Should set fee to 0 (no impact)
    assertEq(_getProtocolFees(pool), 0);
  }

  function test_edge_maximumFees_success() public {
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, 10 << 4 | 10);

    feeAdapter.triggerFeeUpdate(pool);
    assertEq(_getProtocolFees(pool), 10 << 4 | 10);
  }

  function test_edge_minimumFees_success() public {
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, 4 << 4 | 4);

    feeAdapter.triggerFeeUpdate(pool);
    assertEq(_getProtocolFees(pool), 4 << 4 | 4);
  }

  function test_edge_asymmetricFees_success() public {
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, 10 << 4 | 0);

    feeAdapter.triggerFeeUpdate(pool);
    assertEq(_getProtocolFees(pool), 10 << 4 | 0);
  }

  function test_edge_newPoolImmediateUpdate_success() public {
    uint8 protocolFee = 10 << 4 | 8;
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, protocolFee);

    // Create and initialize pool
    MockERC20 newToken = new MockERC20("NewToken", "NEW", 18);
    address newPool = factory.createPool(address(newToken), address(mockToken1), 3000);
    IUniswapV3Pool(newPool).initialize(SQRT_PRICE_1_1);

    // Update immediately after creation
    feeAdapter.triggerFeeUpdate(newPool);

    assertEq(_getProtocolFees(newPool), protocolFee);
  }

  function test_edge_multipleUpdatesChangingDefaults() public {
    uint8[] memory feeSequence = new uint8[](5);
    feeSequence[0] = 10 << 4 | 8;
    feeSequence[1] = 9 << 4 | 7;
    feeSequence[2] = 8 << 4 | 6;
    feeSequence[3] = 7 << 4 | 5;
    feeSequence[4] = 6 << 4 | 4;

    for (uint256 i = 0; i < feeSequence.length; i++) {
      vm.prank(feeSetter);
      feeAdapter.setDefaultFeeByFeeTier(3000, feeSequence[i]);

      feeAdapter.triggerFeeUpdate(pool);

      assertEq(_getProtocolFees(pool), feeSequence[i]);
    }
  }

  // ============ Access Control Tests ============

  function test_setFactoryOwner() public {
    address newOwner = makeAddr("newOwner");
    vm.prank(owner);
    feeAdapter.setFactoryOwner(newOwner);
    assertEq(factory.owner(), newOwner);
  }

  function test_setFactoryOwner_reverts(address caller) public {
    vm.assume(caller != owner);
    vm.prank(caller);
    vm.expectRevert("UNAUTHORIZED");
    feeAdapter.setFactoryOwner(address(0));
  }

  function test_setFeeSetter_emitsEvent() public {
    address oldFeeSetter = feeAdapter.feeSetter();
    address newFeeSetter = makeAddr("newFeeSetter");
    vm.prank(owner);
    vm.expectEmit(true, true, false, false, address(feeAdapter));
    emit IV3OpenFeeAdapter.FeeSetterUpdated(oldFeeSetter, newFeeSetter);
    feeAdapter.setFeeSetter(newFeeSetter);
  }

  function test_setFeeSetter_revertsUnauthorized() public {
    vm.expectRevert("UNAUTHORIZED");
    vm.prank(makeAddr("rando"));
    feeAdapter.setFeeSetter(address(this));
  }

  // ============ Fee Validation Tests ============

  function testFuzz_setDefaultFeeByFeeTier(uint24 feeTier, uint8 defaultFee) public {
    vm.startPrank(feeAdapter.feeSetter());

    // Check if fee tier is valid
    if (factory.feeAmountTickSpacing(feeTier) == 0) {
      vm.expectRevert(IV3OpenFeeAdapter.InvalidFeeTier.selector);
      feeAdapter.setDefaultFeeByFeeTier(feeTier, defaultFee);
    } else {
      // Check if fee value is valid
      uint8 feeProtocol0 = defaultFee % 16;
      uint8 feeProtocol1 = defaultFee >> 4;
      bool isValidFeeValue = (feeProtocol0 == 0 || (feeProtocol0 >= 4 && feeProtocol0 <= 10))
        && (feeProtocol1 == 0 || (feeProtocol1 >= 4 && feeProtocol1 <= 10));

      if (!isValidFeeValue) {
        vm.expectRevert(IV3OpenFeeAdapter.InvalidFeeValue.selector);
        feeAdapter.setDefaultFeeByFeeTier(feeTier, defaultFee);
      } else {
        feeAdapter.setDefaultFeeByFeeTier(feeTier, defaultFee);
        assertEq(feeAdapter.defaultFees(feeTier), defaultFee);
      }
    }

    vm.stopPrank();
  }

  function testFuzz_revert_setDefaultFeeByFeeTier(address caller, uint24 feeTier, uint8 defaultFee)
    public
  {
    vm.assume(caller != feeAdapter.feeSetter());

    vm.prank(caller);
    vm.expectRevert(IV3OpenFeeAdapter.Unauthorized.selector);
    feeAdapter.setDefaultFeeByFeeTier(feeTier, defaultFee);
  }

  function test_setDefaultFeeByFeeTier_revertsWithInvalidFeeTier() public {
    vm.prank(feeSetter);
    vm.expectRevert(IV3OpenFeeAdapter.InvalidFeeTier.selector);
    feeAdapter.setDefaultFeeByFeeTier(11_000, 10);
  }

  function test_setDefaultFeeByFeeTier_revertsWithInvalidFeeValue_255() public {
    // Test with 255 (decomposes to 15, 15 - both invalid)
    uint8 invalidFeeValue = 255;
    // Verify it decomposes to (15, 15)
    assertEq(invalidFeeValue % 16, 15);
    assertEq(invalidFeeValue >> 4, 15);

    vm.prank(feeSetter);
    vm.expectRevert(IV3OpenFeeAdapter.InvalidFeeValue.selector);
    feeAdapter.setDefaultFeeByFeeTier(3000, invalidFeeValue);
  }

  function test_setDefaultFeeByFeeTier_revertsWithInvalidFeeValue_lowerBitsOutOfRange() public {
    // Test with lower 4 bits out of range (e.g., 11)
    uint8 invalidFee = (5 << 4) | 11; // Upper: 5 (valid), Lower: 11 (invalid)
    vm.prank(feeSetter);
    vm.expectRevert(IV3OpenFeeAdapter.InvalidFeeValue.selector);
    feeAdapter.setDefaultFeeByFeeTier(3000, invalidFee);
  }

  function test_setDefaultFeeByFeeTier_revertsWithInvalidFeeValue_upperBitsOutOfRange() public {
    // Test with upper 4 bits out of range (e.g., 12)
    uint8 invalidFee = (12 << 4) | 5; // Upper: 12 (invalid), Lower: 5 (valid)
    vm.prank(feeSetter);
    vm.expectRevert(IV3OpenFeeAdapter.InvalidFeeValue.selector);
    feeAdapter.setDefaultFeeByFeeTier(3000, invalidFee);
  }

  function test_setDefaultFeeByFeeTier_revertsWithInvalidFeeValue_bothBitsInvalidRange() public {
    // Test with both bits in invalid range [1-3]
    uint8 invalidFee = (2 << 4) | 3; // Upper: 2 (invalid), Lower: 3 (invalid)
    vm.prank(feeSetter);
    vm.expectRevert(IV3OpenFeeAdapter.InvalidFeeValue.selector);
    feeAdapter.setDefaultFeeByFeeTier(3000, invalidFee);
  }

  // ============ Integration Tests ============

  function test_integration_updateThenCollect_success() public {
    // Set and trigger fee update
    uint8 protocolFee = 10 << 4 | 8;
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, protocolFee);
    feeAdapter.triggerFeeUpdate(pool);

    // Simulate protocol fees accrual
    uint128 amount0 = 10e18;
    uint128 amount1 = 11e18;
    _mockSetProtocolFees(amount0, amount1);

    // Collect fees
    IV3OpenFeeAdapter.CollectParams[] memory collectParams =
      new IV3OpenFeeAdapter.CollectParams[](1);
    collectParams[0] = IV3OpenFeeAdapter.CollectParams({
      pool: pool, amount0Requested: amount0, amount1Requested: amount1
    });

    address token0 = IUniswapV3Pool(pool).token0();
    address token1 = IUniswapV3Pool(pool).token1();

    uint256 balBefore0 = MockERC20(token0).balanceOf(address(tokenJar));
    uint256 balBefore1 = MockERC20(token1).balanceOf(address(tokenJar));

    feeAdapter.collect(collectParams);

    assertGt(MockERC20(token0).balanceOf(address(tokenJar)), balBefore0);
    assertGt(MockERC20(token1).balanceOf(address(tokenJar)), balBefore1);
  }

  function test_integration_updateMultipleFeeTiers_success() public {
    // Create pool for 500 tier
    address pool500 = factory.createPool(address(mockToken), address(mockToken1), 500);
    IUniswapV3Pool(pool500).initialize(SQRT_PRICE_1_1);

    // Setup multiple fee tiers
    vm.startPrank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(500, 10 << 4 | 9);
    feeAdapter.setDefaultFeeByFeeTier(3000, 9 << 4 | 8);
    feeAdapter.setDefaultFeeByFeeTier(10_000, 8 << 4 | 7);
    vm.stopPrank();

    // Update all pools
    feeAdapter.triggerFeeUpdate(pool500);
    feeAdapter.triggerFeeUpdate(pool);
    feeAdapter.triggerFeeUpdate(pool1);

    assertEq(_getProtocolFees(pool500), 10 << 4 | 9);
    assertEq(_getProtocolFees(pool), 9 << 4 | 8);
    assertEq(_getProtocolFees(pool1), 8 << 4 | 7);
  }

  function test_integration_ownerChangesDefault_usersPropagate() public {
    // Create 5 pools
    address[] memory pools = new address[](5);
    for (uint256 i = 0; i < 5; i++) {
      MockERC20 token = new MockERC20(string.concat("Token", vm.toString(i)), "TKN", 18);
      pools[i] = factory.createPool(address(token), address(mockToken1), 3000);
      IUniswapV3Pool(pools[i]).initialize(SQRT_PRICE_1_1);
    }

    // Initial default
    uint8 initialFee = 10 << 4 | 8;
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, initialFee);

    // Users propagate
    for (uint256 i = 0; i < 5; i++) {
      feeAdapter.triggerFeeUpdate(pools[i]);
    }

    // Verify all have initial fee
    for (uint256 i = 0; i < 5; i++) {
      assertEq(_getProtocolFees(pools[i]), initialFee);
    }

    // Owner changes default
    uint8 newFee = 9 << 4 | 7;
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, newFee);

    // Users propagate new fees
    for (uint256 i = 0; i < 5; i++) {
      feeAdapter.triggerFeeUpdate(pools[i]);
    }

    // Verify all have new fee
    for (uint256 i = 0; i < 5; i++) {
      assertEq(_getProtocolFees(pools[i]), newFee);
    }
  }

  function test_integration_enableNewTierAndUpdate_success() public {
    // Enable new fee tier
    vm.prank(owner);
    feeAdapter.enableFeeAmount(750, 15);

    // Set default for new tier
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(750, 10 << 4 | 8);

    // Create pool with new tier
    address newPool = factory.createPool(address(mockToken), address(mockToken1), 750);
    IUniswapV3Pool(newPool).initialize(SQRT_PRICE_1_1);

    // Update immediately
    feeAdapter.triggerFeeUpdate(newPool);

    assertEq(_getProtocolFees(newPool), 10 << 4 | 8);
  }

  // ============ Gas Benchmark Tests ============

  function test_gas_singlePoolUpdate() public {
    uint8 protocolFee = 10 << 4 | 8;
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, protocolFee);

    // Cold update
    feeAdapter.triggerFeeUpdate(pool);
    vm.snapshotGasLastCall("V3OpenFeeAdapter_triggerFeeUpdate_cold");

    // Change default to enable another update
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, 9 << 4 | 7);

    // Warm update
    feeAdapter.triggerFeeUpdate(pool);
    vm.snapshotGasLastCall("V3OpenFeeAdapter_triggerFeeUpdate_warm");
  }

  function test_gas_batchUpdate10Pools() public {
    address[] memory pools = new address[](10);
    for (uint256 i = 0; i < 10; i++) {
      MockERC20 token = new MockERC20("Token", "TKN", 18);
      pools[i] = factory.createPool(address(token), address(mockToken1), 3000);
      IUniswapV3Pool(pools[i]).initialize(SQRT_PRICE_1_1);
    }

    uint8 protocolFee = 10 << 4 | 8;
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, protocolFee);

    feeAdapter.batchTriggerFeeUpdateByPool(pools);
    vm.snapshotGasLastCall("V3OpenFeeAdapter_batchUpdate_10pools");
  }

  // ==══════════ Waterfall Resolution Tests ══════════==

  function test_getFee_returnsZeroWhenNothingSet() public view {
    // No defaults, no tier defaults, no pool overrides
    assertEq(feeAdapter.getFee(pool), 0);
  }

  function test_getFee_returnsGlobalDefault() public {
    // Set global default (6 | 6 = 0x66 = 1/6 fee)
    uint8 globalDefault = 6 << 4 | 6;
    vm.prank(feeSetter);
    feeAdapter.setDefaultFee(globalDefault);

    assertEq(feeAdapter.getFee(pool), globalDefault);
  }

  function test_getFee_tierDefaultOverridesGlobalDefault() public {
    uint8 globalDefault = 6 << 4 | 6;
    uint8 tierDefault = 4 << 4 | 4;

    vm.startPrank(feeSetter);
    feeAdapter.setDefaultFee(globalDefault);
    feeAdapter.setFeeTierDefault(3000, tierDefault);
    vm.stopPrank();

    assertEq(feeAdapter.getFee(pool), tierDefault);
  }

  function test_getFee_poolOverrideOverridesTierDefault() public {
    uint8 globalDefault = 6 << 4 | 6;
    uint8 tierDefault = 4 << 4 | 4;
    uint8 poolOverride = 5 << 4 | 5;

    vm.startPrank(feeSetter);
    feeAdapter.setDefaultFee(globalDefault);
    feeAdapter.setFeeTierDefault(3000, tierDefault);
    feeAdapter.setPoolOverride(pool, poolOverride);
    vm.stopPrank();

    assertEq(feeAdapter.getFee(pool), poolOverride);
  }

  function test_getFee_zeroPoolOverrideDisablesFees() public {
    uint8 tierDefault = 6 << 4 | 6;

    vm.startPrank(feeSetter);
    feeAdapter.setFeeTierDefault(3000, tierDefault);
    feeAdapter.setPoolOverride(pool, 0);
    vm.stopPrank();

    assertEq(feeAdapter.getFee(pool), 0);
  }

  function test_getFee_zeroTierDefaultDisablesFees() public {
    uint8 globalDefault = 6 << 4 | 6;

    vm.startPrank(feeSetter);
    feeAdapter.setDefaultFee(globalDefault);
    feeAdapter.setFeeTierDefault(3000, 0);
    vm.stopPrank();

    assertEq(feeAdapter.getFee(pool), 0);
  }

  function test_clearPoolOverride_fallsBackToTierDefault() public {
    uint8 tierDefault = 6 << 4 | 6;
    uint8 poolOverride = 4 << 4 | 4;

    vm.startPrank(feeSetter);
    feeAdapter.setFeeTierDefault(3000, tierDefault);
    feeAdapter.setPoolOverride(pool, poolOverride);
    vm.stopPrank();

    assertEq(feeAdapter.getFee(pool), poolOverride);

    vm.prank(feeSetter);
    feeAdapter.clearPoolOverride(pool);

    assertEq(feeAdapter.getFee(pool), tierDefault);
  }

  function test_clearFeeTierDefault_fallsBackToGlobalDefault() public {
    uint8 globalDefault = 5 << 4 | 5;
    uint8 tierDefault = 6 << 4 | 6;

    vm.startPrank(feeSetter);
    feeAdapter.setDefaultFee(globalDefault);
    feeAdapter.setFeeTierDefault(3000, tierDefault);
    vm.stopPrank();

    assertEq(feeAdapter.getFee(pool), tierDefault);

    // Clear tier default
    vm.prank(feeSetter);
    feeAdapter.clearFeeTierDefault(3000);

    // Should fall back to global default
    assertEq(feeAdapter.getFee(pool), globalDefault);
  }

  function test_fullWaterfallChain() public {
    // Set all three levels
    uint8 globalDefault = 4 << 4 | 4;
    uint8 tierDefault = 5 << 4 | 5;
    uint8 poolOverride = 6 << 4 | 6;

    vm.startPrank(feeSetter);
    feeAdapter.setDefaultFee(globalDefault);
    feeAdapter.setFeeTierDefault(3000, tierDefault);
    feeAdapter.setPoolOverride(pool, poolOverride);
    vm.stopPrank();

    // Pool override takes precedence
    assertEq(feeAdapter.getFee(pool), poolOverride);

    // Clear pool override → tier default
    vm.prank(feeSetter);
    feeAdapter.clearPoolOverride(pool);
    assertEq(feeAdapter.getFee(pool), tierDefault);

    // Clear tier default → global default
    vm.prank(feeSetter);
    feeAdapter.clearFeeTierDefault(3000);
    assertEq(feeAdapter.getFee(pool), globalDefault);
  }

  function test_setDefaultFee_onlyFeeSetter() public {
    vm.expectRevert(IV3OpenFeeAdapter.Unauthorized.selector);
    vm.prank(alice);
    feeAdapter.setDefaultFee(4 << 4 | 4);
  }

  function test_setFeeTierDefault_onlyFeeSetter() public {
    vm.expectRevert(IV3OpenFeeAdapter.Unauthorized.selector);
    vm.prank(alice);
    feeAdapter.setFeeTierDefault(3000, 4 << 4 | 4);
  }

  function test_setPoolOverride_onlyFeeSetter() public {
    vm.expectRevert(IV3OpenFeeAdapter.Unauthorized.selector);
    vm.prank(alice);
    feeAdapter.setPoolOverride(pool, 4 << 4 | 4);
  }

  function test_setDefaultFee_revertsWithInvalidFeeValue() public {
    vm.expectRevert(IV3OpenFeeAdapter.InvalidFeeValue.selector);
    vm.prank(feeSetter);
    feeAdapter.setDefaultFee(3 << 4 | 3); // 3 is out of range [4,10]
  }

  function test_setFeeTierDefault_revertsWithInvalidFeeValue() public {
    vm.expectRevert(IV3OpenFeeAdapter.InvalidFeeValue.selector);
    vm.prank(feeSetter);
    feeAdapter.setFeeTierDefault(3000, 11 << 4 | 11); // 11 is out of range [4,10]
  }

  function test_setPoolOverride_revertsWithInvalidFeeValue() public {
    vm.expectRevert(IV3OpenFeeAdapter.InvalidFeeValue.selector);
    vm.prank(feeSetter);
    feeAdapter.setPoolOverride(pool, 2 << 4 | 2); // 2 is out of range [4,10]
  }

  function test_setDefaultFee_emitsEvent() public {
    uint8 feeValue = 6 << 4 | 6;
    vm.expectEmit(false, false, false, true);
    emit IV3OpenFeeAdapter.DefaultFeeUpdated(feeValue);
    vm.prank(feeSetter);
    feeAdapter.setDefaultFee(feeValue);
  }

  function test_setFeeTierDefault_emitsEvent() public {
    uint8 feeValue = 5 << 4 | 5;
    vm.expectEmit(true, false, false, true);
    emit IV3OpenFeeAdapter.FeeTierDefaultUpdated(3000, feeValue);
    vm.prank(feeSetter);
    feeAdapter.setFeeTierDefault(3000, feeValue);
  }

  function test_setPoolOverride_emitsEvent() public {
    uint8 feeValue = 4 << 4 | 4;
    vm.expectEmit(true, false, false, true);
    emit IV3OpenFeeAdapter.PoolOverrideUpdated(pool, feeValue);
    vm.prank(feeSetter);
    feeAdapter.setPoolOverride(pool, feeValue);
  }

  function test_clearFeeTierDefault_emitsEvent() public {
    // First set a tier default
    vm.prank(feeSetter);
    feeAdapter.setFeeTierDefault(3000, 5 << 4 | 5);

    // Clear it - should emit distinct clear event
    vm.expectEmit(true, false, false, true);
    emit IV3OpenFeeAdapter.FeeTierDefaultCleared(3000);
    vm.prank(feeSetter);
    feeAdapter.clearFeeTierDefault(3000);
  }

  function test_clearPoolOverride_emitsEvent() public {
    // First set a pool override
    vm.prank(feeSetter);
    feeAdapter.setPoolOverride(pool, 4 << 4 | 4);

    // Clear it - should emit distinct clear event
    vm.expectEmit(true, false, false, true);
    emit IV3OpenFeeAdapter.PoolOverrideCleared(pool);
    vm.prank(feeSetter);
    feeAdapter.clearPoolOverride(pool);
  }

  function test_triggerFeeUpdate_usesWaterfallResolution() public {
    // Set tier default
    uint8 tierDefault = 6 << 4 | 6;
    vm.prank(feeSetter);
    feeAdapter.setFeeTierDefault(3000, tierDefault);

    // Trigger fee update
    feeAdapter.triggerFeeUpdate(pool);

    // Verify fee was set on pool
    (,,,,, uint8 protocolFee,) = IUniswapV3Pool(pool).slot0();
    assertEq(protocolFee, tierDefault);
  }

  function test_triggerFeeUpdate_poolOverrideTakesPrecedence() public {
    // Set tier default
    uint8 tierDefault = 6 << 4 | 6;
    vm.prank(feeSetter);
    feeAdapter.setFeeTierDefault(3000, tierDefault);

    // Set pool override
    uint8 poolOverride = 4 << 4 | 4;
    vm.prank(feeSetter);
    feeAdapter.setPoolOverride(pool, poolOverride);

    // Trigger fee update
    feeAdapter.triggerFeeUpdate(pool);

    // Verify pool override was applied
    (,,,,, uint8 protocolFee,) = IUniswapV3Pool(pool).slot0();
    assertEq(protocolFee, poolOverride);
  }

  function test_legacyDefaultFees_returnsDecodedValue() public {
    // Set tier default using new function
    uint8 tierDefault = 5 << 4 | 5;
    vm.prank(feeSetter);
    feeAdapter.setFeeTierDefault(3000, tierDefault);

    // Legacy getter should return the same value
    assertEq(feeAdapter.defaultFees(3000), tierDefault);
  }

  function test_legacyDefaultFees_returnsZeroForUnset() public view {
    // Unset tier should return 0
    assertEq(feeAdapter.defaultFees(3000), 0);
  }

  function test_legacySetDefaultFeeByFeeTier_setsFeeTierDefault() public {
    uint8 feeValue = 6 << 4 | 6;
    vm.prank(feeSetter);
    feeAdapter.setDefaultFeeByFeeTier(3000, feeValue);

    // Both legacy and new getter should return the value
    assertEq(feeAdapter.defaultFees(3000), feeValue);
    // feeTierDefaults stores the encoded value (same as feeValue since non-zero)
    assertEq(feeAdapter.feeTierDefaults(3000), feeValue);
  }

  function test_ZERO_FEE_SENTINEL_constant() public view {
    assertEq(feeAdapter.ZERO_FEE_SENTINEL(), type(uint8).max);
  }

  // ============ Legacy defaultFees Waterfall Tests (L-02) ============

  function test_defaultFees_waterfallsToGlobalDefault() public {
    uint8 globalDefault = 6 << 4 | 6;
    vm.prank(feeSetter);
    feeAdapter.setDefaultFee(globalDefault);

    // No tier default set — should fall through to global default
    assertEq(feeAdapter.defaultFees(3000), globalDefault);
  }

  function test_defaultFees_tierDefaultTakesPrecedenceOverGlobal() public {
    uint8 globalDefault = 6 << 4 | 6;
    uint8 tierDefault = 4 << 4 | 4;

    vm.startPrank(feeSetter);
    feeAdapter.setDefaultFee(globalDefault);
    feeAdapter.setFeeTierDefault(3000, tierDefault);
    vm.stopPrank();

    assertEq(feeAdapter.defaultFees(3000), tierDefault);
  }

  function test_defaultFees_returnsZeroWhenNothingConfigured() public view {
    // Neither tier default nor global default set
    assertEq(feeAdapter.defaultFees(3000), 0);
  }

  function test_defaultFees_clearTierDefault_fallsBackToGlobal() public {
    uint8 globalDefault = 5 << 4 | 5;
    uint8 tierDefault = 7 << 4 | 7;

    vm.startPrank(feeSetter);
    feeAdapter.setDefaultFee(globalDefault);
    feeAdapter.setFeeTierDefault(3000, tierDefault);
    vm.stopPrank();

    assertEq(feeAdapter.defaultFees(3000), tierDefault);

    vm.prank(feeSetter);
    feeAdapter.clearFeeTierDefault(3000);

    assertEq(feeAdapter.defaultFees(3000), globalDefault);
  }

  function test_defaultFees_explicitZeroTierDefault_returnsZero() public {
    uint8 globalDefault = 6 << 4 | 6;

    vm.startPrank(feeSetter);
    feeAdapter.setDefaultFee(globalDefault);
    feeAdapter.setFeeTierDefault(3000, 0); // Explicit zero disables
    vm.stopPrank();

    // Explicit zero should NOT waterfall to global — fees are intentionally disabled
    assertEq(feeAdapter.defaultFees(3000), 0);
  }

  // ============ Distinct Event Tests (L-03) ============

  function test_clearEvent_differsFromSetToZeroEvent() public {
    // Set a tier default, then explicitly set to zero — emits FeeTierDefaultUpdated
    vm.prank(feeSetter);
    feeAdapter.setFeeTierDefault(3000, 5 << 4 | 5);

    vm.recordLogs();
    vm.prank(feeSetter);
    feeAdapter.setFeeTierDefault(3000, 0);
    Vm.Log[] memory setLogs = vm.getRecordedLogs();

    // Set it again before clearing
    vm.prank(feeSetter);
    feeAdapter.setFeeTierDefault(3000, 5 << 4 | 5);

    // Clear it — emits FeeTierDefaultCleared
    vm.recordLogs();
    vm.prank(feeSetter);
    feeAdapter.clearFeeTierDefault(3000);
    Vm.Log[] memory clearLogs = vm.getRecordedLogs();

    // The event signatures should differ
    assertTrue(setLogs.length > 0 && clearLogs.length > 0);
    assertTrue(
      setLogs[0].topics[0] != clearLogs[0].topics[0],
      "Set-to-zero and clear should emit different event signatures"
    );
  }

  function test_clearPoolEvent_differsFromSetToZeroEvent() public {
    vm.prank(feeSetter);
    feeAdapter.setPoolOverride(pool, 4 << 4 | 4);

    vm.recordLogs();
    vm.prank(feeSetter);
    feeAdapter.setPoolOverride(pool, 0);
    Vm.Log[] memory setLogs = vm.getRecordedLogs();

    vm.prank(feeSetter);
    feeAdapter.setPoolOverride(pool, 4 << 4 | 4);

    vm.recordLogs();
    vm.prank(feeSetter);
    feeAdapter.clearPoolOverride(pool);
    Vm.Log[] memory clearLogs = vm.getRecordedLogs();

    assertTrue(setLogs.length > 0 && clearLogs.length > 0);
    assertTrue(
      setLogs[0].topics[0] != clearLogs[0].topics[0],
      "Set-to-zero and clear should emit different event signatures"
    );
  }

  // ============ Helper Functions ============

  function _mockSetProtocolFees(uint128 token0, uint128 token1) internal {
    uint256 toSet = uint256(token1) << 128 | uint256(token0);
    vm.store(pool, bytes32(slot), bytes32(toSet));
  }

  function _getProtocolFees(address _pool) internal view returns (uint8 poolFeesPacked) {
    (,,,,, uint8 poolFees,) = IUniswapV3Pool(_pool).slot0();
    return poolFees;
  }

  function _toPair(address tokenA, address tokenB)
    internal
    pure
    returns (IV3OpenFeeAdapter.Pair memory)
  {
    if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
    return IV3OpenFeeAdapter.Pair({token0: tokenA, token1: tokenB});
  }
}
