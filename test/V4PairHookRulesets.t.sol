// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";

import {V4FeePolicy} from "../src/feeAdapters/V4FeePolicy.sol";
import {IV4FeePolicy, IV4ProtocolFeeRuleset} from "../src/interfaces/IV4FeePolicy.sol";
import {V4StaticCurveRuleset} from "../src/feeAdapters/rulesets/V4StaticCurveRuleset.sol";
import {FeeBucket} from "../src/interfaces/IV4StaticCurveRuleset.sol";
import {IV4PairHookRuleset} from "../src/interfaces/IV4PairHookRuleset.sol";
import {V4StablePairHookRuleset} from "../src/feeAdapters/rulesets/V4StablePairHookRuleset.sol";
import {V4VolatilePairHookRuleset} from "../src/feeAdapters/rulesets/V4VolatilePairHookRuleset.sol";
import {MockStablePairHook, MockVolatilePairHook} from "./mocks/MockPairHooks.sol";

/// @dev Each section starts with the branch tree of one function. The tests are in the same
/// sequence as the tree. setUp registers the curve of proposal 6 for hookless pools.
contract V4PairHookRulesetsTest is Test {
  using PoolIdLibrary for PoolKey;

  /// @dev The rulesets key of pools that have no hook.
  address internal constant NO_HOOK = address(0);

  /// @dev The maximum optimal fee of the StablePairHook, in pips.
  uint24 internal constant MAX_OPTIMAL_FEE_E6 = 10_000;

  V4FeePolicy public policy;
  V4StaticCurveRuleset public curve;
  MockStablePairHook public stableHook;
  MockVolatilePairHook public volatileHook;
  V4StablePairHookRuleset public stableRuleset;
  V4VolatilePairHookRuleset public volatileRuleset;

  function setUp() public {
    policy = new V4FeePolicy(address(this), address(this));
    curve = new V4StaticCurveRuleset(_proposal6Buckets());
    policy.setProtocolFeeRuleset(NO_HOOK, curve);

    stableHook = new MockStablePairHook();
    volatileHook = new MockVolatilePairHook();
    stableRuleset = new V4StablePairHookRuleset(policy);
    volatileRuleset = new V4VolatilePairHookRuleset(policy);
  }

  /// @dev The curve of proposal 6, in pips.
  function _proposal6Buckets() internal pure returns (FeeBucket[] memory buckets) {
    buckets = new FeeBucket[](8);
    buckets[0] = FeeBucket({lpFeeFloor: 0, alphaPips: 1, betaPips: 0});
    buckets[1] = FeeBucket({lpFeeFloor: 3, alphaPips: 1, betaPips: 263_889});
    buckets[2] = FeeBucket({lpFeeFloor: 75, alphaPips: 20, betaPips: 200_000});
    buckets[3] = FeeBucket({lpFeeFloor: 100, alphaPips: 25, betaPips: 272_728});
    buckets[4] = FeeBucket({lpFeeFloor: 375, alphaPips: 100, betaPips: 200_000});
    buckets[5] = FeeBucket({lpFeeFloor: 500, alphaPips: 125, betaPips: 137_500});
    buckets[6] = FeeBucket({lpFeeFloor: 2500, alphaPips: 400, betaPips: 200_000});
    buckets[7] = FeeBucket({lpFeeFloor: 5500, alphaPips: 1000, betaPips: 0});
  }

  /// @dev A dynamic-fee pool on `hook`.
  function _key(address hook, uint256 salt) internal pure returns (PoolKey memory key) {
    key.currency0 = Currency.wrap(address(uint160(0x1000 + salt % 1000)));
    key.currency1 = Currency.wrap(address(uint160(0x3000)));
    key.fee = LPFeeLibrary.DYNAMIC_FEE_FLAG;
    key.tickSpacing = 1;
    key.hooks = IHooks(hook);
  }

  // ============ constructor ============
  //
  // constructor
  // ├── when the policy is the zero address
  // │   └── it reverts with AddressCannotBeZero
  // └── when the policy is not the zero address
  //     └── it sets the policy

  function test_constructor_RevertWhen_ThePolicyIsTheZeroAddress() public {
    vm.expectRevert(IV4PairHookRuleset.AddressCannotBeZero.selector);
    new V4StablePairHookRuleset(IV4FeePolicy(address(0)));

    vm.expectRevert(IV4PairHookRuleset.AddressCannotBeZero.selector);
    new V4VolatilePairHookRuleset(IV4FeePolicy(address(0)));
  }

  function test_constructor_SetsThePolicy() public view {
    assertEq(address(stableRuleset.POLICY()), address(policy));
    assertEq(address(volatileRuleset.POLICY()), address(policy));
  }

  // ============ getProtocolFee ============
  //
  // getProtocolFee
  // ├── given no ruleset is set for hookless pools
  // │   └── it reverts with HooklessCurveNotSet
  // └── given a curve is set for hookless pools
  //     ├── given the StablePairHook ruleset
  //     │   └── it returns the curve fee for the optimal fee of the pool
  //     ├── given the VolatilePairHook ruleset
  //     │   └── it returns the curve fee for half of the resting spread, rounded down
  //     └── when the hookless curve changes
  //         └── it returns the fee of the new curve

  function testFuzz_getProtocolFee_RevertWhen_NoRulesetIsSetForHooklessPools(uint256 salt) public {
    // Given: no ruleset is set for hookless pools.
    policy.setProtocolFeeRuleset(NO_HOOK, IV4ProtocolFeeRuleset(address(0)));

    // Then: getProtocolFee reverts with HooklessCurveNotSet.
    vm.expectRevert(IV4PairHookRuleset.HooklessCurveNotSet.selector);
    stableRuleset.getProtocolFee(_key(address(stableHook), salt));

    vm.expectRevert(IV4PairHookRuleset.HooklessCurveNotSet.selector);
    volatileRuleset.getProtocolFee(_key(address(volatileHook), salt));
  }

  function testFuzz_getProtocolFee_GivenTheStablePairHookRuleset(uint256 salt, uint24 optimalFeeE6)
    public
  {
    // Given: a pool with an optimal fee.
    PoolKey memory key = _key(address(stableHook), salt);
    optimalFeeE6 = uint24(bound(optimalFeeE6, 0, MAX_OPTIMAL_FEE_E6));
    stableHook.setOptimalFee(key.toId(), optimalFeeE6);

    // Then: getProtocolFee returns the curve fee for the optimal fee.
    assertEq(stableRuleset.lpFee(key), optimalFeeE6);
    assertEq(stableRuleset.getProtocolFee(key), curve.getFeeForLpFee(optimalFeeE6));
  }

  function testFuzz_getProtocolFee_GivenTheVolatilePairHookRuleset(
    uint256 salt,
    uint24 restingSpreadE6
  ) public {
    // Given: a pool with a resting spread.
    PoolKey memory key = _key(address(volatileHook), salt);
    restingSpreadE6 = uint24(bound(restingSpreadE6, 0, LPFeeLibrary.MAX_LP_FEE));
    volatileHook.setRestingSpread(key.toId(), restingSpreadE6);

    // Then: getProtocolFee returns the curve fee for half of the resting spread, rounded down.
    assertEq(volatileRuleset.lpFee(key), restingSpreadE6 / 2);
    assertEq(volatileRuleset.getProtocolFee(key), curve.getFeeForLpFee(restingSpreadE6 / 2));
  }

  function testFuzz_getProtocolFee_WhenTheHooklessCurveChanges(
    uint256 salt,
    uint24 optimalFeeE6,
    uint24 restingSpreadE6,
    uint24 alphaPips
  ) public {
    // Given: a stable pool and a volatile pool.
    PoolKey memory stableKey = _key(address(stableHook), salt);
    PoolKey memory volatileKey = _key(address(volatileHook), salt);
    stableHook.setOptimalFee(stableKey.toId(), uint24(bound(optimalFeeE6, 0, MAX_OPTIMAL_FEE_E6)));
    volatileHook.setRestingSpread(
      volatileKey.toId(), uint24(bound(restingSpreadE6, 0, LPFeeLibrary.MAX_LP_FEE))
    );

    // When: governance sets a flat curve for hookless pools.
    alphaPips = uint24(bound(alphaPips, 0, 1000));
    FeeBucket[] memory flat = new FeeBucket[](1);
    flat[0] = FeeBucket({lpFeeFloor: 0, alphaPips: alphaPips, betaPips: 0});
    policy.setProtocolFeeRuleset(NO_HOOK, new V4StaticCurveRuleset(flat));

    // Then: getProtocolFee returns the fee of the new curve.
    uint24 expected = alphaPips << 12 | alphaPips;
    assertEq(stableRuleset.getProtocolFee(stableKey), expected);
    assertEq(volatileRuleset.getProtocolFee(volatileKey), expected);
  }

  // ============ Examples ============

  function test_stablePairHook_optimalFeeOf0_9Bps_pays0_23Bps() public {
    // 1 + 263_889 * (90 - 3) / 1_000_000 = 23 pips.
    PoolKey memory key = _key(address(stableHook), 0);
    stableHook.setOptimalFee(key.toId(), 90);
    assertEq(stableRuleset.getProtocolFee(key), 23 << 12 | 23);
  }

  function test_volatilePairHook_restingSpreadOf60Bps_pays5Bps() public {
    // Half of the spread is 30 bps, and the curve gives 5 bps for an LP fee of 30 bps.
    PoolKey memory key = _key(address(volatileHook), 0);
    volatileHook.setRestingSpread(key.toId(), 6000);
    assertEq(volatileRuleset.getProtocolFee(key), 500 << 12 | 500);
  }

  // ============ V4FeePolicy integration ============

  function testFuzz_policy_returnsTheRulesetFeeForAssignedPairHooks(
    uint256 salt,
    uint24 optimalFeeE6,
    uint24 restingSpreadE6
  ) public {
    // Given: each ruleset is assigned to its hook.
    policy.setProtocolFeeRuleset(address(stableHook), stableRuleset);
    policy.setProtocolFeeRuleset(address(volatileHook), volatileRuleset);

    PoolKey memory stableKey = _key(address(stableHook), salt);
    PoolKey memory volatileKey = _key(address(volatileHook), salt);
    optimalFeeE6 = uint24(bound(optimalFeeE6, 0, MAX_OPTIMAL_FEE_E6));
    restingSpreadE6 = uint24(bound(restingSpreadE6, 0, LPFeeLibrary.MAX_LP_FEE));
    stableHook.setOptimalFee(stableKey.toId(), optimalFeeE6);
    volatileHook.setRestingSpread(volatileKey.toId(), restingSpreadE6);

    // Then: the policy returns the curve fee for each dynamic-fee pool.
    assertEq(policy.computeFee(stableKey), curve.getFeeForLpFee(optimalFeeE6));
    assertEq(policy.computeFee(volatileKey), curve.getFeeForLpFee(restingSpreadE6 / 2));
  }
}
