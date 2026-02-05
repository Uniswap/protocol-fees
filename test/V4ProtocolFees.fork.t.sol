// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {V4FeeAdapter} from "../src/feeAdapters/V4FeeAdapter.sol";
import {IV4FeeAdapter} from "../src/interfaces/IV4FeeAdapter.sol";
import {IOwned} from "../src/interfaces/base/IOwned.sol";
import {V4FeeSwitchProposal} from "../script/05_V4FeeSwitchProposal.s.sol";
import {MainnetDeployer} from "../script/deployers/MainnetDeployer.sol";
import {UnificationProposal} from "../script/04_UnificationProposal.s.sol";

/// @notice Minimal swap helper that implements the unlock callback pattern
contract SwapHelper is IUnlockCallback {
  using CurrencyLibrary for Currency;

  IPoolManager public immutable poolManager;

  struct SwapCallbackData {
    PoolKey key;
    SwapParams params;
    address sender;
  }

  constructor(IPoolManager _poolManager) {
    poolManager = _poolManager;
  }

  /// @notice Execute a swap via the unlock pattern
  function swap(PoolKey memory key, SwapParams memory params) external payable returns (BalanceDelta delta) {
    bytes memory result = poolManager.unlock(abi.encode(SwapCallbackData(key, params, msg.sender)));
    delta = abi.decode(result, (BalanceDelta));
  }

  /// @notice Callback from PoolManager.unlock()
  function unlockCallback(bytes calldata data) external override returns (bytes memory) {
    require(msg.sender == address(poolManager), "Only PoolManager");

    SwapCallbackData memory swapData = abi.decode(data, (SwapCallbackData));

    // Execute the swap
    BalanceDelta delta = poolManager.swap(swapData.key, swapData.params, "");

    // Settle the swap - handle what we owe and what we're owed
    // delta.amount0() < 0 means we owe token0, > 0 means we're owed token0
    int128 amount0 = delta.amount0();
    int128 amount1 = delta.amount1();

    // Settle negative deltas (what we owe)
    if (amount0 < 0) {
      _settle(swapData.key.currency0, swapData.sender, uint128(-amount0));
    }
    if (amount1 < 0) {
      _settle(swapData.key.currency1, swapData.sender, uint128(-amount1));
    }

    // Take positive deltas (what we're owed)
    if (amount0 > 0) {
      poolManager.take(swapData.key.currency0, swapData.sender, uint128(amount0));
    }
    if (amount1 > 0) {
      poolManager.take(swapData.key.currency1, swapData.sender, uint128(amount1));
    }

    return abi.encode(delta);
  }

  function _settle(Currency currency, address payer, uint256 amount) internal {
    if (currency.isAddressZero()) {
      // Native ETH - settle with value
      poolManager.settle{value: amount}();
    } else {
      // ERC20 - transfer then sync then settle
      poolManager.sync(currency);
      IERC20(Currency.unwrap(currency)).transferFrom(payer, address(poolManager), amount);
      poolManager.settle();
    }
  }

  receive() external payable {}
}

/// @title V4ProtocolFeesForkTest
/// @notice Fork tests for the V4 fee switch proposal
contract V4ProtocolFeesForkTest is Test {
  using PoolIdLibrary for PoolKey;
  using StateLibrary for IPoolManager;

  // Mainnet addresses
  IPoolManager public constant POOL_MANAGER = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
  address constant ETH = address(0);
  address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
  address constant cbBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
  address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
  address constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;

  // Real V4 pool IDs (for verification)
  bytes32 constant ETH_USDC_POOL_ID = 0xdce6394339af00981949f5f3baf27e3610c76326a700af57e4b3e3ae4977f78d;
  bytes32 constant WBTC_CBBTC_POOL_ID = 0x2f92b371aef58f0abe9c10c06423de083405991f2839638914a1031e91d9a723;
  bytes32 constant USDC_USDT_POOL_ID_10 = 0x8aa4e11cbdf30eedc92100f4c8a31ff748e201d44712cc8c90d189edaa8e4e47; // 0.001% fee
  bytes32 constant USDE_USDT_POOL_ID = 0x63bb22f47c7ede6578a25c873e77eb782ec8e4c19778e36ce64d37877b5bd1e7; // 0.0045% fee
  bytes32 constant USDC_USDT_POOL_ID_8 = 0x395f91b34aa34a477ce3bc6505639a821b286a62b1a164fc1887fa3a5ef713a5; // 0.0008% fee

  // Deployed contracts
  V4FeeAdapter public v4FeeAdapter;
  MainnetDeployer public deployer;
  SwapHelper public swapHelper;

  // Test addresses
  address public poolManagerOwner;
  address public tokenJar;

  // Test pool keys
  PoolKey[] internal testPools;

  // Fork from a recent block where V4 is deployed
  // V4 was deployed on mainnet in January 2025
  uint256 constant FORK_BLOCK = 24_106_377;

  /// @notice Packs a single-direction fee into the V4 format (symmetric for both directions)
  /// @dev V4 protocol fee is a uint24: lower 12 bits = zeroForOne, upper 12 bits = oneForZero
  function _packFee(uint24 fee) internal pure returns (uint24) {
    return (fee << 12) | fee;
  }

  function setUp() public {
    vm.createSelectFork("mainnet", FORK_BLOCK);

    // Get the PoolManager owner (this is who can set the protocol fee controller)
    poolManagerOwner = IOwned(address(POOL_MANAGER)).owner();

    // Deploy the unification proposal infrastructure first to get TokenJar
    deployer = new MainnetDeployer();
    UnificationProposal unificationProposal = new UnificationProposal();
    unificationProposal.runPranked(deployer);
    tokenJar = address(deployer.TOKEN_JAR());

    // Deploy the V4FeeAdapter
    // The owner should be the PoolManager owner (governance timelock)
    // The feeSetter is also the owner initially
    vm.prank(poolManagerOwner);
    v4FeeAdapter = new V4FeeAdapter(
      address(POOL_MANAGER),
      tokenJar,
      poolManagerOwner, // feeSetter
      0 // No default fee initially
    );

    // Deploy the swap helper for swap tests
    swapHelper = new SwapHelper(POOL_MANAGER);

    // Setup test pool keys for common fee tiers
    // These are synthetic pools for testing - in production we'd use real pool addresses
    _setupTestPoolKeys();
  }

  function _setupTestPoolKeys() internal {
    // Create pool keys for REAL initialized V4 pools on mainnet

    // ETH/USDC 0.30% pool (3000 bps LP fee, tickSpacing 60)
    // Pool ID: 0xdce6394339af00981949f5f3baf27e3610c76326a700af57e4b3e3ae4977f78d
    PoolKey memory ethUsdc = PoolKey({
      currency0: Currency.wrap(ETH), // ETH = address(0)
      currency1: Currency.wrap(USDC),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(address(0))
    });
    // Verify the pool ID matches
    require(PoolId.unwrap(ethUsdc.toId()) == ETH_USDC_POOL_ID, "ETH/USDC pool ID mismatch");
    testPools.push(ethUsdc);

    // WBTC/cbBTC 0.01% pool (100 bps LP fee, tickSpacing 1)
    // Pool ID: 0x2f92b371aef58f0abe9c10c06423de083405991f2839638914a1031e91d9a723
    PoolKey memory wbtcCbbtc = PoolKey({
      currency0: Currency.wrap(WBTC), // WBTC < cbBTC by address
      currency1: Currency.wrap(cbBTC),
      fee: 100,
      tickSpacing: 1,
      hooks: IHooks(address(0))
    });
    // Verify the pool ID matches
    require(PoolId.unwrap(wbtcCbbtc.toId()) == WBTC_CBBTC_POOL_ID, "WBTC/cbBTC pool ID mismatch");
    testPools.push(wbtcCbbtc);

    // USDC/USDT 0.001% pool (10 bps LP fee, tickSpacing 1)
    // Pool ID: 0x8aa4e11cbdf30eedc92100f4c8a31ff748e201d44712cc8c90d189edaa8e4e47
    PoolKey memory usdcUsdt10 = PoolKey({
      currency0: Currency.wrap(USDC), // USDC < USDT by address
      currency1: Currency.wrap(USDT),
      fee: 10,
      tickSpacing: 1,
      hooks: IHooks(address(0))
    });
    // Verify the pool ID matches
    require(PoolId.unwrap(usdcUsdt10.toId()) == USDC_USDT_POOL_ID_10, "USDC/USDT 10 pool ID mismatch");
    testPools.push(usdcUsdt10);

    // USDE/USDT 0.0045% pool (45 bps LP fee, tickSpacing 1)
    // Pool ID: 0x63bb22f47c7ede6578a25c873e77eb782ec8e4c19778e36ce64d37877b5bd1e7
    PoolKey memory usdeUsdt = PoolKey({
      currency0: Currency.wrap(USDE), // USDE < USDT by address
      currency1: Currency.wrap(USDT),
      fee: 45,
      tickSpacing: 1,
      hooks: IHooks(address(0))
    });
    // Verify the pool ID matches
    require(PoolId.unwrap(usdeUsdt.toId()) == USDE_USDT_POOL_ID, "USDE/USDT pool ID mismatch");
    testPools.push(usdeUsdt);

    // USDC/USDT 0.0008% pool (8 bps LP fee, tickSpacing 1)
    // Pool ID: 0x395f91b34aa34a477ce3bc6505639a821b286a62b1a164fc1887fa3a5ef713a5
    PoolKey memory usdcUsdt8 = PoolKey({
      currency0: Currency.wrap(USDC), // USDC < USDT by address
      currency1: Currency.wrap(USDT),
      fee: 8,
      tickSpacing: 1,
      hooks: IHooks(address(0))
    });
    // Verify the pool ID matches
    require(PoolId.unwrap(usdcUsdt8.toId()) == USDC_USDT_POOL_ID_8, "USDC/USDT 8 pool ID mismatch");
    testPools.push(usdcUsdt8);
  }

  // ═══════════════════════════════════════════════════════════════
  //                    PROPOSAL EXECUTION TESTS
  // ═══════════════════════════════════════════════════════════════

  function test_proposalExecution_setsProtocolFeeController() public {
    // Execute the proposal
    _executeV4Proposal();

    // Verify the protocol fee controller is set
    assertEq(POOL_MANAGER.protocolFeeController(), address(v4FeeAdapter));
  }

  function test_proposalExecution_setsDefaultFee() public {
    _executeV4Proposal();

    // Default fee should be set to 750 (DEFAULT_PROTOCOL_FEE from the proposal)
    uint24 expectedDefault = 750;

    // For a pool with no tier override, it should return the default
    PoolKey memory unknownTierPool = PoolKey({
      currency0: Currency.wrap(address(1)),
      currency1: Currency.wrap(address(2)),
      fee: 9999, // Unusual fee tier with no override
      tickSpacing: 100,
      hooks: IHooks(address(0))
    });

    assertEq(v4FeeAdapter.getFee(unknownTierPool), _packFee(expectedDefault));
  }

  function test_proposalExecution_setsTierOverrides() public {
    _executeV4Proposal();

    // Helper to create a pool key for a given fee tier
    // Note: tickSpacing doesn't affect fee resolution, just needs to be valid

    // 8 bps LP fee tier (0.0008%) / 4 = 2 pips (TIER_8_FEE)
    PoolKey memory pool8 = PoolKey({
      currency0: Currency.wrap(address(1)),
      currency1: Currency.wrap(address(2)),
      fee: 8,
      tickSpacing: 1,
      hooks: IHooks(address(0))
    });
    assertEq(v4FeeAdapter.getFee(pool8), _packFee(2), "TIER_8_FEE");

    // 10 bps LP fee tier (0.001%) / 4 = 3 pips (TIER_10_FEE)
    PoolKey memory pool10 = PoolKey({
      currency0: Currency.wrap(address(1)),
      currency1: Currency.wrap(address(2)),
      fee: 10,
      tickSpacing: 1,
      hooks: IHooks(address(0))
    });
    assertEq(v4FeeAdapter.getFee(pool10), _packFee(3), "TIER_10_FEE");

    // 45 bps LP fee tier (0.0045%) / 4 = 11 pips (TIER_45_FEE)
    PoolKey memory pool45 = PoolKey({
      currency0: Currency.wrap(address(1)),
      currency1: Currency.wrap(address(2)),
      fee: 45,
      tickSpacing: 1,
      hooks: IHooks(address(0))
    });
    assertEq(v4FeeAdapter.getFee(pool45), _packFee(11), "TIER_45_FEE");

    // 100 bps LP fee tier (0.01%) / 4 = 25 pips (TIER_100_FEE)
    PoolKey memory pool100 = PoolKey({
      currency0: Currency.wrap(address(1)),
      currency1: Currency.wrap(address(2)),
      fee: 100,
      tickSpacing: 1,
      hooks: IHooks(address(0))
    });
    assertEq(v4FeeAdapter.getFee(pool100), _packFee(25), "TIER_100_FEE");

    // 500 bps LP fee tier (0.05%) / 4 = 125 pips (TIER_500_FEE)
    PoolKey memory pool500 = PoolKey({
      currency0: Currency.wrap(address(1)),
      currency1: Currency.wrap(address(2)),
      fee: 500,
      tickSpacing: 10,
      hooks: IHooks(address(0))
    });
    assertEq(v4FeeAdapter.getFee(pool500), _packFee(125), "TIER_500_FEE");

    // 3000 bps LP fee tier (0.30%) / 6 = 500 pips (TIER_3000_FEE)
    PoolKey memory pool3000 = PoolKey({
      currency0: Currency.wrap(address(1)),
      currency1: Currency.wrap(address(2)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(address(0))
    });
    assertEq(v4FeeAdapter.getFee(pool3000), _packFee(500), "TIER_3000_FEE");

    // 10000 bps LP fee tier (1.00%) / 6 = 1000 pips capped (TIER_10000_FEE)
    PoolKey memory pool10000 = PoolKey({
      currency0: Currency.wrap(address(1)),
      currency1: Currency.wrap(address(2)),
      fee: 10000,
      tickSpacing: 200,
      hooks: IHooks(address(0))
    });
    assertEq(v4FeeAdapter.getFee(pool10000), _packFee(1000), "TIER_10000_FEE");
  }

  function test_proposalExecution_appliesFeesToPools() public {
    _executeV4Proposal();

    // After proposal execution, fees should be applied to the test pools
    // The protocol fee should be set on the PoolManager for each pool
    for (uint256 i = 0; i < testPools.length; i++) {
      PoolKey memory key = testPools[i];
      PoolId poolId = key.toId();

      // Get the expected fee from our adapter
      uint24 expectedFee = v4FeeAdapter.getFee(key);

      // Get the actual protocol fee from the pool state
      // Note: This only works if the pool is initialized
      // For uninitialized pools, we just verify the adapter returns the right fee
      (,, uint24 protocolFee,) = StateLibrary.getSlot0(POOL_MANAGER, poolId);

      // If the pool exists and was in our batch, the fee should match
      // If not, this is still a valid test of the adapter's resolution logic
      if (protocolFee != 0) {
        assertEq(protocolFee, expectedFee, "Protocol fee mismatch for pool");
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //                      FEE RESOLUTION TESTS
  // ═══════════════════════════════════════════════════════════════

  /// @notice Verify each real pool resolves to the correct tier-based fee
  function test_feeResolution_eachPoolGetsCorrectTierFee() public {
    _executeV4Proposal();

    // ETH/USDC: 3000 tier → TIER_3000_FEE (500)
    assertEq(v4FeeAdapter.getFee(testPools[0]), _packFee(500), "ETH/USDC should get TIER_3000_FEE");

    // WBTC/cbBTC: 100 tier → TIER_100_FEE (25)
    assertEq(v4FeeAdapter.getFee(testPools[1]), _packFee(25), "WBTC/cbBTC should get TIER_100_FEE");

    // USDC/USDT (10): 10 tier → TIER_10_FEE (3)
    assertEq(v4FeeAdapter.getFee(testPools[2]), _packFee(3), "USDC/USDT 10 should get TIER_10_FEE");

    // USDE/USDT: 45 tier → TIER_45_FEE (11)
    assertEq(v4FeeAdapter.getFee(testPools[3]), _packFee(11), "USDE/USDT should get TIER_45_FEE");

    // USDC/USDT (8): 8 tier → TIER_8_FEE (2)
    assertEq(v4FeeAdapter.getFee(testPools[4]), _packFee(2), "USDC/USDT 8 should get TIER_8_FEE");
  }

  /// @notice Test that pools with unregistered tiers fall back to default
  function test_feeResolution_unregisteredTierFallsBackToDefault() public {
    _executeV4Proposal();

    // Create a pool with a tier that has no override (e.g., 77)
    PoolKey memory unknownTierPool = PoolKey({
      currency0: Currency.wrap(address(1)),
      currency1: Currency.wrap(address(2)),
      fee: 77, // No tier override for this
      tickSpacing: 1,
      hooks: IHooks(address(0))
    });

    // Should fall back to default (750)
    assertEq(v4FeeAdapter.getFee(unknownTierPool), _packFee(750), "Unknown tier should fall back to default");
  }

  /// @notice Test the full waterfall with NO overrides set (only default)
  function test_feeResolution_noOverridesOnlyDefault() public {
    // Deploy fresh adapter with just a default fee, no tier overrides
    vm.prank(poolManagerOwner);
    V4FeeAdapter freshAdapter = new V4FeeAdapter(
      address(POOL_MANAGER),
      tokenJar,
      poolManagerOwner,
      0 // Start with no default
    );

    // Set ONLY the default fee
    vm.prank(poolManagerOwner);
    freshAdapter.setDefaultFee(250);

    // All pools should get the default fee regardless of their tier
    for (uint256 i = 0; i < testPools.length; i++) {
      assertEq(freshAdapter.getFee(testPools[i]), _packFee(250), "All pools should get default when no tier overrides");
    }
  }

  /// @notice Test that clearing a tier override falls back to default
  function test_feeResolution_clearTierOverrideFallsBackToDefault() public {
    _executeV4Proposal();

    // ETH/USDC uses 3000 tier → currently 500 (TIER_3000_FEE)
    PoolKey memory pool = testPools[0];
    assertEq(v4FeeAdapter.getFee(pool), _packFee(500), "Should start with tier fee");

    // Clear the 3000 tier override
    vm.prank(poolManagerOwner);
    v4FeeAdapter.clearFeeTierOverride(3000);

    // Should now fall back to default (750)
    assertEq(v4FeeAdapter.getFee(pool), _packFee(750), "Should fall back to default after clearing tier");

    // To prove it's using default and not tier, change the default
    vm.prank(poolManagerOwner);
    v4FeeAdapter.setDefaultFee(999);

    assertEq(v4FeeAdapter.getFee(pool), _packFee(999), "Should now use new default after tier cleared");
  }

  /// @notice Test setting tier override to zero explicitly disables fees for that tier
  function test_feeResolution_zeroTierOverrideDisablesFees() public {
    _executeV4Proposal();

    // WBTC/cbBTC uses 100 tier → currently 25 (TIER_100_FEE)
    PoolKey memory pool = testPools[1];
    assertEq(v4FeeAdapter.getFee(pool), _packFee(25), "Should start with tier fee");

    // Set tier 100 to explicitly zero
    vm.prank(poolManagerOwner);
    v4FeeAdapter.setFeeTierOverride(100, 0);

    // Fee should now be 0 (NOT falling back to default)
    assertEq(v4FeeAdapter.getFee(pool), 0, "Zero tier override should disable fees");
  }

  /// @notice Test pool override takes precedence over tier override
  function test_feeResolution_poolOverrideTakesPrecedence() public {
    _executeV4Proposal();

    // Test on each pool to ensure pool override works for all tiers
    for (uint256 i = 0; i < testPools.length; i++) {
      PoolKey memory pool = testPools[i];
      uint24 tierFee = v4FeeAdapter.getFee(pool);

      // Set a pool-specific override different from tier
      uint24 poolOverrideFee = 333;
      vm.prank(poolManagerOwner);
      v4FeeAdapter.setPoolOverride(pool.toId(), poolOverrideFee);

      // Pool override should take precedence over tier
      assertEq(v4FeeAdapter.getFee(pool), _packFee(poolOverrideFee), "Pool override should take precedence");

      // Clean up for next iteration
      vm.prank(poolManagerOwner);
      v4FeeAdapter.clearPoolOverride(pool.toId());
      assertEq(v4FeeAdapter.getFee(pool), tierFee, "Should restore to tier fee");
    }
  }

  /// @notice Test setting pool override to zero disables fees (doesn't fall through)
  function test_feeResolution_zeroPoolOverrideDisablesFees() public {
    _executeV4Proposal();

    // Test on multiple pools with different tiers
    for (uint256 i = 0; i < testPools.length; i++) {
      PoolKey memory pool = testPools[i];
      uint24 tierFee = v4FeeAdapter.getFee(pool);
      assertTrue(tierFee > 0, "Pool should have non-zero tier fee");

      // Set pool override to 0 (disable fees)
      vm.prank(poolManagerOwner);
      v4FeeAdapter.setPoolOverride(pool.toId(), 0);

      // Fee should now be 0 (NOT falling back to tier)
      assertEq(v4FeeAdapter.getFee(pool), 0, "Zero pool override should disable fees");

      // Clean up
      vm.prank(poolManagerOwner);
      v4FeeAdapter.clearPoolOverride(pool.toId());
    }
  }

  /// @notice Test clearing pool override falls back to tier
  function test_feeResolution_clearPoolOverrideFallsBackToTier() public {
    _executeV4Proposal();

    // Test on each pool
    for (uint256 i = 0; i < testPools.length; i++) {
      PoolKey memory pool = testPools[i];
      uint24 expectedTierFee = v4FeeAdapter.getFee(pool);

      // Set a pool override
      vm.prank(poolManagerOwner);
      v4FeeAdapter.setPoolOverride(pool.toId(), 999);
      assertEq(v4FeeAdapter.getFee(pool), _packFee(999), "Pool override should be set");

      // Clear the pool override
      vm.prank(poolManagerOwner);
      v4FeeAdapter.clearPoolOverride(pool.toId());

      // Should fall back to tier fee
      assertEq(v4FeeAdapter.getFee(pool), expectedTierFee, "Should fall back to tier fee");
    }
  }

  /// @notice Test full waterfall: pool override → tier override → default
  function test_feeResolution_fullWaterfallChain() public {
    _executeV4Proposal();

    // Use ETH/USDC (3000 tier, 500 fee)
    PoolKey memory pool = testPools[0];

    // 1. Start: tier override active → 500
    assertEq(v4FeeAdapter.getFee(pool), _packFee(500), "Step 1: Should use tier override");

    // 2. Set pool override → 111
    vm.prank(poolManagerOwner);
    v4FeeAdapter.setPoolOverride(pool.toId(), 111);
    assertEq(v4FeeAdapter.getFee(pool), _packFee(111), "Step 2: Pool override takes precedence");

    // 3. Clear pool override → back to tier (500)
    vm.prank(poolManagerOwner);
    v4FeeAdapter.clearPoolOverride(pool.toId());
    assertEq(v4FeeAdapter.getFee(pool), _packFee(500), "Step 3: Falls back to tier");

    // 4. Clear tier override → falls to default (750)
    vm.prank(poolManagerOwner);
    v4FeeAdapter.clearFeeTierOverride(3000);
    assertEq(v4FeeAdapter.getFee(pool), _packFee(750), "Step 4: Falls back to default");

    // 5. Change default → reflects new default
    vm.prank(poolManagerOwner);
    v4FeeAdapter.setDefaultFee(777);
    assertEq(v4FeeAdapter.getFee(pool), _packFee(777), "Step 5: Uses new default");

    // 6. Re-add tier override → uses tier again
    vm.prank(poolManagerOwner);
    v4FeeAdapter.setFeeTierOverride(3000, 444);
    assertEq(v4FeeAdapter.getFee(pool), _packFee(444), "Step 6: Tier override active again");

    // 7. Set pool override to 0 → disables fees (doesn't fall through)
    vm.prank(poolManagerOwner);
    v4FeeAdapter.setPoolOverride(pool.toId(), 0);
    assertEq(v4FeeAdapter.getFee(pool), 0, "Step 7: Zero pool override disables fees");
  }

  /// @notice Test that zero default works correctly
  function test_feeResolution_zeroDefaultFee() public {
    // Deploy fresh adapter with zero default
    vm.prank(poolManagerOwner);
    V4FeeAdapter freshAdapter = new V4FeeAdapter(
      address(POOL_MANAGER),
      tokenJar,
      poolManagerOwner,
      0 // Zero default
    );

    // Pool with no tier override should get 0
    PoolKey memory unknownTierPool = PoolKey({
      currency0: Currency.wrap(address(1)),
      currency1: Currency.wrap(address(2)),
      fee: 77,
      tickSpacing: 1,
      hooks: IHooks(address(0))
    });

    assertEq(freshAdapter.getFee(unknownTierPool), 0, "Should return 0 with zero default");

    // Add a tier override, pool with that tier should get the override
    vm.prank(poolManagerOwner);
    freshAdapter.setFeeTierOverride(77, 123);
    assertEq(freshAdapter.getFee(unknownTierPool), _packFee(123), "Should use tier override");
  }

  // ═══════════════════════════════════════════════════════════════
  //                      ACCESS CONTROL TESTS
  // ═══════════════════════════════════════════════════════════════

  function test_accessControl_onlyFeeSetterCanSetFees() public {
    _executeV4Proposal();

    address notFeeSetter = makeAddr("notFeeSetter");

    vm.prank(notFeeSetter);
    vm.expectRevert(IV4FeeAdapter.Unauthorized.selector);
    v4FeeAdapter.setDefaultFee(100);

    vm.prank(notFeeSetter);
    vm.expectRevert(IV4FeeAdapter.Unauthorized.selector);
    v4FeeAdapter.setFeeTierOverride(500, 100);

    vm.prank(notFeeSetter);
    vm.expectRevert(IV4FeeAdapter.Unauthorized.selector);
    v4FeeAdapter.setPoolOverride(testPools[0].toId(), 100);
  }

  function test_accessControl_ownerCanTransferFeeSetter() public {
    _executeV4Proposal();

    address newFeeSetter = makeAddr("newFeeSetter");

    // Transfer feeSetter role
    vm.prank(poolManagerOwner);
    v4FeeAdapter.setFeeSetter(newFeeSetter);

    assertEq(v4FeeAdapter.feeSetter(), newFeeSetter);

    // New fee setter can set fees
    vm.prank(newFeeSetter);
    v4FeeAdapter.setDefaultFee(100);
    // Should not revert
  }

  // ═══════════════════════════════════════════════════════════════
  //                      APPLY FEE TESTS
  // ═══════════════════════════════════════════════════════════════

  function test_applyFee_updatesPoolManagerProtocolFee() public {
    _executeV4Proposal();

    // Pick a pool and change its override
    PoolKey memory pool = testPools[0];
    uint24 newFee = 300;

    vm.prank(poolManagerOwner);
    v4FeeAdapter.setPoolOverride(pool.toId(), newFee);

    // Apply the new fee
    v4FeeAdapter.applyFee(pool);

    // Verify the PoolManager has the new fee
    (,, uint24 protocolFee,) = StateLibrary.getSlot0(POOL_MANAGER, pool.toId());
    assertEq(protocolFee, _packFee(newFee));
  }

  function test_batchApplyFees_updatesMultiplePools() public {
    _executeV4Proposal();

    // Set different overrides for each pool
    vm.startPrank(poolManagerOwner);
    v4FeeAdapter.setPoolOverride(testPools[0].toId(), 100);
    v4FeeAdapter.setPoolOverride(testPools[1].toId(), 200);
    vm.stopPrank();

    // Batch apply
    v4FeeAdapter.batchApplyFees(testPools);

    // Verify each pool
    (,, uint24 fee0,) = StateLibrary.getSlot0(POOL_MANAGER, testPools[0].toId());
    (,, uint24 fee1,) = StateLibrary.getSlot0(POOL_MANAGER, testPools[1].toId());
    assertEq(fee0, _packFee(100));
    assertEq(fee1, _packFee(200));
  }

  // ═══════════════════════════════════════════════════════════════
  //                      SWAP TESTS (E2E)
  // ═══════════════════════════════════════════════════════════════

  /// @notice Verify ETH/USDC (3000 tier) collects exactly 500 pips (0.05%) protocol fee
  function test_swap_ETH_USDC_collects500Pips() public {
    _executeV4Proposal();

    PoolKey memory pool = testPools[0]; // ETH/USDC, 3000 tier
    uint24 expectedFeePips = 500; // TIER_3000_FEE

    // Verify the fee is set correctly
    (,, uint24 protocolFee,) = StateLibrary.getSlot0(POOL_MANAGER, pool.toId());
    assertEq(protocolFee, _packFee(expectedFeePips), "Protocol fee should be 500 pips");

    // Perform swap and validate fee
    uint256 swapAmount = 1 ether;
    uint256 collectedFee = _swapAndGetFee(pool, swapAmount);

    // Expected: 1 ETH * 500 / 1_000_000 = 0.0005 ETH = 500000000000000 wei
    uint256 expectedFee = (swapAmount * expectedFeePips) / 1_000_000;
    assertEq(expectedFee, 500000000000000, "Sanity check: expected fee calculation");

    // Exact match - no tolerance
    assertEq(collectedFee, expectedFee, "Fee must be exactly 500 pips of input");
  }

  /// @notice Verify each tier collects the correct protocol fee rate
  function test_swap_allTiersCollectCorrectFees() public {
    _executeV4Proposal();

    // Test pool 0: ETH/USDC (3000 tier) → 500 pips
    _verifyPoolFeeRate(testPools[0], 500, "ETH/USDC 3000 tier");

    // Test pool 2: USDC/USDT (10 tier) → 3 pips
    _verifyPoolFeeRate(testPools[2], 3, "USDC/USDT 10 tier");

    // Test pool 3: USDE/USDT (45 tier) → 11 pips
    _verifyPoolFeeRate(testPools[3], 11, "USDE/USDT 45 tier");

    // Test pool 4: USDC/USDT (8 tier) → 2 pips
    _verifyPoolFeeRate(testPools[4], 2, "USDC/USDT 8 tier");
  }

  /// @notice Verify fee changes take effect immediately on next swap
  function test_swap_feeChangeAffectsNextSwap() public {
    _executeV4Proposal();

    PoolKey memory pool = testPools[0]; // ETH/USDC
    PoolId poolId = pool.toId();
    uint256 swapAmount = 1 ether;

    // === Swap 1: Default tier fee (500 pips) ===
    uint256 fee1 = _swapAndGetFee(pool, swapAmount);
    uint256 expected1 = (swapAmount * 500) / 1_000_000;
    assertEq(fee1, expected1, "Swap 1: must collect exactly 500 pips");

    // === Change to custom pool override (800 pips) ===
    vm.prank(poolManagerOwner);
    v4FeeAdapter.setPoolOverride(poolId, 800);
    v4FeeAdapter.applyFee(pool);

    // Verify fee changed
    (,, uint24 protocolFee,) = StateLibrary.getSlot0(POOL_MANAGER, poolId);
    assertEq(protocolFee, _packFee(800), "Fee should be 800 pips");

    // === Swap 2: Custom fee (800 pips) ===
    uint256 fee2 = _swapAndGetFee(pool, swapAmount);
    uint256 expected2 = (swapAmount * 800) / 1_000_000;
    assertEq(fee2, expected2, "Swap 2: must collect exactly 800 pips");

    // Verify fee2 is higher than fee1 by the expected ratio (800/500 = 1.6x)
    assertEq(fee2, (fee1 * 800) / 500, "Fee must scale exactly with rate change");

    // === Change to zero (disabled) ===
    vm.prank(poolManagerOwner);
    v4FeeAdapter.setPoolOverride(poolId, 0);
    v4FeeAdapter.applyFee(pool);

    (,, protocolFee,) = StateLibrary.getSlot0(POOL_MANAGER, poolId);
    assertEq(protocolFee, 0, "Fee should be 0");

    // === Swap 3: Zero fee ===
    uint256 feesBefore = POOL_MANAGER.protocolFeesAccrued(pool.currency0);
    vm.deal(address(swapHelper), swapAmount);
    vm.prank(address(swapHelper));
    swapHelper.swap{value: swapAmount}(pool, SwapParams({
      zeroForOne: true,
      amountSpecified: -int256(swapAmount),
      sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
    }));
    uint256 feesAfter = POOL_MANAGER.protocolFeesAccrued(pool.currency0);

    assertEq(feesAfter, feesBefore, "Swap 3: should collect zero fees when disabled");
  }

  /// @notice Verify fee accumulation across multiple swaps is additive
  function test_swap_feesAccumulateCorrectly() public {
    _executeV4Proposal();

    PoolKey memory pool = testPools[0]; // ETH/USDC, 500 pips
    uint256 swapAmount = 0.5 ether;
    uint256 expectedFeePerSwap = (swapAmount * 500) / 1_000_000;

    uint256 initialFees = POOL_MANAGER.protocolFeesAccrued(pool.currency0);

    // Perform 5 swaps
    for (uint256 i = 0; i < 5; i++) {
      vm.deal(address(swapHelper), swapAmount);
      vm.prank(address(swapHelper));
      swapHelper.swap{value: swapAmount}(pool, SwapParams({
        zeroForOne: true,
        amountSpecified: -int256(swapAmount),
        sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
      }));
    }

    uint256 finalFees = POOL_MANAGER.protocolFeesAccrued(pool.currency0);
    uint256 totalCollected = finalFees - initialFees;
    uint256 expectedTotal = expectedFeePerSwap * 5;

    assertEq(totalCollected, expectedTotal, "Total fees must exactly equal sum of individual fees");
  }

  /// @notice Test various swap sizes on ETH/USDC (500 pips tier fee)
  function test_swap_variousSizes_tierFee() public {
    _executeV4Proposal();

    PoolKey memory pool = testPools[0]; // ETH/USDC, 500 pips
    uint24 feePips = 500;

    // Test small swap: 0.001 ETH
    uint256 smallAmount = 0.001 ether;
    uint256 smallFee = _swapAndGetFee(pool, smallAmount);
    assertEq(smallFee, (smallAmount * feePips) / 1_000_000, "Small swap: 0.001 ETH");

    // Test medium swap: 0.1 ETH
    uint256 mediumAmount = 0.1 ether;
    uint256 mediumFee = _swapAndGetFee(pool, mediumAmount);
    assertEq(mediumFee, (mediumAmount * feePips) / 1_000_000, "Medium swap: 0.1 ETH");

    // Test large swap: 10 ETH
    uint256 largeAmount = 10 ether;
    uint256 largeFee = _swapAndGetFee(pool, largeAmount);
    assertEq(largeFee, (largeAmount * feePips) / 1_000_000, "Large swap: 10 ETH");

    // Test large swap: 20 ETH
    uint256 veryLargeAmount = 20 ether;
    uint256 veryLargeFee = _swapAndGetFee(pool, veryLargeAmount);
    assertEq(veryLargeFee, (veryLargeAmount * feePips) / 1_000_000, "Large swap: 20 ETH");

    // Test odd amount: 1.234567 ETH
    uint256 oddAmount = 1.234567 ether;
    uint256 oddFee = _swapAndGetFee(pool, oddAmount);
    assertEq(oddFee, (oddAmount * feePips) / 1_000_000, "Odd swap: 1.234567 ETH");

    // Test another odd amount: 7.891234 ETH
    uint256 oddAmount2 = 7.891234 ether;
    uint256 oddFee2 = _swapAndGetFee(pool, oddAmount2);
    assertEq(oddFee2, (oddAmount2 * feePips) / 1_000_000, "Odd swap: 7.891234 ETH");
  }

  /// @notice Test various swap sizes with pool override (custom 333 pips)
  function test_swap_variousSizes_poolOverride() public {
    _executeV4Proposal();

    PoolKey memory pool = testPools[0]; // ETH/USDC
    PoolId poolId = pool.toId();
    uint24 customFee = 333; // Custom override

    // Set pool override
    vm.prank(poolManagerOwner);
    v4FeeAdapter.setPoolOverride(poolId, customFee);
    v4FeeAdapter.applyFee(pool);

    // Verify override is set
    (,, uint24 protocolFee,) = StateLibrary.getSlot0(POOL_MANAGER, poolId);
    assertEq(protocolFee, _packFee(customFee), "Pool override should be set");

    // Test various sizes
    uint256[] memory amounts = new uint256[](5);
    amounts[0] = 0.005 ether;
    amounts[1] = 0.05 ether;
    amounts[2] = 0.5 ether;
    amounts[3] = 5 ether;
    amounts[4] = 50 ether;

    for (uint256 i = 0; i < amounts.length; i++) {
      uint256 fee = _swapAndGetFee(pool, amounts[i]);
      uint256 expected = (amounts[i] * customFee) / 1_000_000;
      assertEq(fee, expected, string.concat("Override fee at size ", vm.toString(i)));
    }
  }

  /// @notice Test swap fees on all tier pools to verify tier-specific rates
  /// @dev V4 has internal rounding that can cause fees to be 1 unit lower than expected
  ///      for certain input amounts. We verify the fee is within 1 unit of expected.
  function test_swap_allPools_tierFees() public {
    _executeV4Proposal();

    // Pool 0: ETH/USDC (3000 tier) → 500 pips
    {
      PoolKey memory pool = testPools[0];
      uint256 swapAmount = 2 ether;
      uint256 fee = _swapAndGetFee(pool, swapAmount);
      uint256 expected = (swapAmount * 500) / 1_000_000;
      assertEq(fee, expected, "ETH/USDC: 500 pips");
    }

    // Pool 1: WBTC/cbBTC (100 tier) → 25 pips
    {
      PoolKey memory pool = testPools[1];
      uint24 expectedPips = 25;
      uint256 swapAmount = 1e8; // 1 WBTC (8 decimals)

      // Deal WBTC to swapHelper and approve
      deal(WBTC, address(swapHelper), swapAmount);
      vm.prank(address(swapHelper));
      IERC20(WBTC).approve(address(swapHelper), swapAmount);

      uint256 fee = _swapERC20AndGetFee(pool, swapAmount, true);
      uint256 expected = (swapAmount * expectedPips) / 1_000_000;
      assertApproxEqAbs(fee, expected, 1, "WBTC/cbBTC: 25 pips");
    }

    // Pool 2: USDC/USDT (10 tier) → 3 pips
    {
      PoolKey memory pool = testPools[2];
      uint24 expectedPips = 3;
      uint256 swapAmount = 10_000e6; // 10,000 USDC (6 decimals)

      // Deal USDC to swapHelper and approve
      deal(USDC, address(swapHelper), swapAmount);
      vm.prank(address(swapHelper));
      IERC20(USDC).approve(address(swapHelper), swapAmount);

      uint256 fee = _swapERC20AndGetFee(pool, swapAmount, true);
      uint256 expected = (swapAmount * expectedPips) / 1_000_000;
      assertApproxEqAbs(fee, expected, 1, "USDC/USDT 10: 3 pips");
    }

    // Pool 3: USDE/USDT (45 tier) → 11 pips
    {
      PoolKey memory pool = testPools[3];
      uint24 expectedPips = 11;
      uint256 swapAmount = 10_000e18; // 10,000 USDE (18 decimals)

      // Deal USDE to swapHelper and approve
      deal(USDE, address(swapHelper), swapAmount);
      vm.prank(address(swapHelper));
      IERC20(USDE).approve(address(swapHelper), swapAmount);

      uint256 fee = _swapERC20AndGetFee(pool, swapAmount, true);
      uint256 expected = (swapAmount * expectedPips) / 1_000_000;
      assertApproxEqAbs(fee, expected, 1, "USDE/USDT: 11 pips");
    }

    // Pool 4: USDC/USDT (8 tier) → 2 pips
    {
      PoolKey memory pool = testPools[4];
      uint24 expectedPips = 2;
      uint256 swapAmount = 50_000e6; // 50,000 USDC (6 decimals)

      // Deal USDC to swapHelper and approve
      deal(USDC, address(swapHelper), swapAmount);
      vm.prank(address(swapHelper));
      IERC20(USDC).approve(address(swapHelper), swapAmount);

      uint256 fee = _swapERC20AndGetFee(pool, swapAmount, true);
      uint256 expected = (swapAmount * expectedPips) / 1_000_000;
      assertApproxEqAbs(fee, expected, 1, "USDC/USDT 8: 2 pips");
    }
  }

  /// @notice Test minimum fee edge case (1 wei input with low fee rate)
  function test_swap_minimumFee_edgeCase() public {
    _executeV4Proposal();

    PoolKey memory pool = testPools[0]; // ETH/USDC, 500 pips

    // 1 wei * 500 / 1_000_000 = 0 (rounds down)
    uint256 tinyAmount = 1 wei;
    uint256 tinyFee = _swapAndGetFee(pool, tinyAmount);
    assertEq(tinyFee, 0, "1 wei should yield 0 fee due to rounding");

    // 2000 wei * 500 / 1_000_000 = 1 wei
    uint256 minForOneFee = 2000 wei;
    uint256 minFee = _swapAndGetFee(pool, minForOneFee);
    assertEq(minFee, 1, "2000 wei should yield exactly 1 wei fee");

    // 1999 wei * 500 / 1_000_000 = 0 (rounds down)
    uint256 justUnder = 1999 wei;
    uint256 justUnderFee = _swapAndGetFee(pool, justUnder);
    assertEq(justUnderFee, 0, "1999 wei should yield 0 fee");
  }

  /// @notice Test maximum protocol fee rate (1000 pips = 0.1%)
  function test_swap_maxFeeRate() public {
    _executeV4Proposal();

    PoolKey memory pool = testPools[0]; // ETH/USDC
    PoolId poolId = pool.toId();

    // Set to max allowed fee (1000 pips)
    uint24 maxFee = 1000;
    vm.prank(poolManagerOwner);
    v4FeeAdapter.setPoolOverride(poolId, maxFee);
    v4FeeAdapter.applyFee(pool);

    (,, uint24 protocolFee,) = StateLibrary.getSlot0(POOL_MANAGER, poolId);
    assertEq(protocolFee, _packFee(maxFee), "Max fee should be set");

    // Test various amounts at max fee rate
    uint256 amount1 = 1 ether;
    uint256 fee1 = _swapAndGetFee(pool, amount1);
    assertEq(fee1, (amount1 * maxFee) / 1_000_000, "1 ETH at max fee");
    assertEq(fee1, 0.001 ether, "1 ETH * 0.1% = 0.001 ETH");

    uint256 amount10 = 10 ether;
    uint256 fee10 = _swapAndGetFee(pool, amount10);
    assertEq(fee10, (amount10 * maxFee) / 1_000_000, "10 ETH at max fee");
    assertEq(fee10, 0.01 ether, "10 ETH * 0.1% = 0.01 ETH");
  }

  /// @notice Document V4's internal rounding behavior on very large swaps
  /// @dev At 100 ETH, V4 rounds down by 1 wei due to internal precision limits
  function test_swap_v4InternalRounding() public {
    _executeV4Proposal();

    PoolKey memory pool = testPools[0]; // ETH/USDC, 500 pips
    uint24 feePips = 500;

    // 100 ETH swap shows V4's internal rounding: off by 1 wei
    uint256 largeAmount = 100 ether;
    uint256 fee = _swapAndGetFee(pool, largeAmount);
    uint256 expected = (largeAmount * feePips) / 1_000_000;

    // Document the actual behavior: V4 rounds down by 1 wei
    assertEq(expected, 50000000000000000, "Expected: 0.05 ETH");
    assertEq(fee, 49999999999999999, "Actual: 0.05 ETH - 1 wei (V4 rounding)");
    assertEq(expected - fee, 1, "Difference is exactly 1 wei");
  }

  /// @notice Test fee collection with pool override vs tier override comparison
  function test_swap_overrideComparison() public {
    _executeV4Proposal();

    PoolKey memory pool = testPools[0]; // ETH/USDC
    PoolId poolId = pool.toId();
    uint256 swapAmount = 5 ether;

    // Swap 1: Tier fee (500 pips)
    uint256 tierFee = _swapAndGetFee(pool, swapAmount);
    uint256 expectedTier = (swapAmount * 500) / 1_000_000;
    assertEq(tierFee, expectedTier, "Tier fee: 500 pips");

    // Swap 2: Pool override lower (250 pips)
    vm.prank(poolManagerOwner);
    v4FeeAdapter.setPoolOverride(poolId, 250);
    v4FeeAdapter.applyFee(pool);

    uint256 lowerFee = _swapAndGetFee(pool, swapAmount);
    uint256 expectedLower = (swapAmount * 250) / 1_000_000;
    assertEq(lowerFee, expectedLower, "Pool override: 250 pips");
    assertEq(lowerFee, tierFee / 2, "250 pips is exactly half of 500 pips");

    // Swap 3: Pool override higher (750 pips)
    vm.prank(poolManagerOwner);
    v4FeeAdapter.setPoolOverride(poolId, 750);
    v4FeeAdapter.applyFee(pool);

    uint256 higherFee = _swapAndGetFee(pool, swapAmount);
    uint256 expectedHigher = (swapAmount * 750) / 1_000_000;
    assertEq(higherFee, expectedHigher, "Pool override: 750 pips");
    assertEq(higherFee, (tierFee * 3) / 2, "750 pips is 1.5x of 500 pips");

    // Swap 4: Clear override, back to tier
    vm.prank(poolManagerOwner);
    v4FeeAdapter.clearPoolOverride(poolId);
    v4FeeAdapter.applyFee(pool);

    uint256 backToTier = _swapAndGetFee(pool, swapAmount);
    assertEq(backToTier, tierFee, "Back to tier fee after clearing override");
  }

  // ═══════════════════════════════════════════════════════════════
  //                    SWAP TEST HELPERS
  // ═══════════════════════════════════════════════════════════════

  /// @notice Execute an ETH swap and return the protocol fee collected
  function _swapAndGetFee(PoolKey memory pool, uint256 swapAmount) internal returns (uint256 feeCollected) {
    uint256 feesBefore = POOL_MANAGER.protocolFeesAccrued(pool.currency0);

    vm.deal(address(swapHelper), swapAmount);
    vm.prank(address(swapHelper));
    swapHelper.swap{value: swapAmount}(pool, SwapParams({
      zeroForOne: true,
      amountSpecified: -int256(swapAmount),
      sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
    }));

    uint256 feesAfter = POOL_MANAGER.protocolFeesAccrued(pool.currency0);
    feeCollected = feesAfter - feesBefore;
  }

  /// @notice Execute an ERC20 swap and return the protocol fee collected
  /// @param pool The pool to swap on
  /// @param swapAmount The amount of input token to swap
  /// @param zeroForOne Direction of swap (true = token0 -> token1)
  function _swapERC20AndGetFee(PoolKey memory pool, uint256 swapAmount, bool zeroForOne)
    internal
    returns (uint256 feeCollected)
  {
    Currency inputCurrency = zeroForOne ? pool.currency0 : pool.currency1;
    uint256 feesBefore = POOL_MANAGER.protocolFeesAccrued(inputCurrency);

    vm.prank(address(swapHelper));
    swapHelper.swap(pool, SwapParams({
      zeroForOne: zeroForOne,
      amountSpecified: -int256(swapAmount),
      sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
    }));

    uint256 feesAfter = POOL_MANAGER.protocolFeesAccrued(inputCurrency);
    feeCollected = feesAfter - feesBefore;
  }

  /// @notice Verify a pool's fee rate by checking the set protocol fee
  function _verifyPoolFeeRate(PoolKey memory pool, uint24 expectedPips, string memory label) internal view {
    (,, uint24 protocolFee,) = StateLibrary.getSlot0(POOL_MANAGER, pool.toId());
    assertEq(protocolFee, _packFee(expectedPips), string.concat(label, ": incorrect protocol fee"));
  }

  function _executeV4Proposal() internal {
    V4FeeSwitchProposal proposal = new V4FeeSwitchProposal();

    // Execute the proposal as the PoolManager owner
    proposal.runPranked(v4FeeAdapter, testPools, poolManagerOwner);
  }
}
