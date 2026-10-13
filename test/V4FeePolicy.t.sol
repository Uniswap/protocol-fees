// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";

import {V4FeePolicy} from "../src/feeAdapters/V4FeePolicy.sol";
import {
  IV4FeePolicy,
  IV4ProtocolFeeRuleset,
  ProtocolFeeRulesetAssignment
} from "../src/interfaces/IV4FeePolicy.sol";
import {MockProtocolFeeRuleset, MockSelfReportingHook} from "./mocks/MockProtocolFeeRuleset.sol";

/// @dev Each section starts with the branch tree of one function. The tests are in the same
/// sequence as the tree. Each test sets all conditions of its branch, thus setUp has no pool or
/// mock state.
contract V4FeePolicyTest is Test {
  /// @dev The four RETURNS_DELTA flags of v4-core. A hook with one or more of these flags does
  /// custom accounting.
  uint160 internal constant RETURNS_DELTA_FLAGS = Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
    | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG
    | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG;

  V4FeePolicy public policy;

  address public owner;
  address public feeSetter;

  function setUp() public {
    owner = makeAddr("owner");
    feeSetter = makeAddr("feeSetter");
    policy = new V4FeePolicy(owner, feeSetter);
  }

  /// @dev Returns `fee` with each 12-bit direction in the range [0, MAX_PROTOCOL_FEE].
  function _boundProtocolFee(uint24 fee) internal pure returns (uint24) {
    uint24 zeroForOne = uint24(bound(fee & 0xFFF, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
    uint24 oneForZero = uint24(bound(fee >> 12, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
    return oneForZero << 12 | zeroForOne;
  }

  // ============ constructor ============
  //
  // constructor
  // └── it sets the owner and the fee setter, and the default fee is zero

  function testFuzz_constructor(address initialOwner, address initialFeeSetter) public {
    vm.expectEmit();
    emit Owned.OwnershipTransferred(address(0), initialOwner);
    V4FeePolicy deployed = new V4FeePolicy(initialOwner, initialFeeSetter);

    assertEq(deployed.owner(), initialOwner);
    assertEq(deployed.feeSetter(), initialFeeSetter);
    assertEq(deployed.defaultFee(), 0);
    assertEq(deployed.CUSTOM_ACCOUNTING_MASK(), RETURNS_DELTA_FLAGS);
    assertEq(deployed.HOOKLESS_POLICY_SENTINEL(), address(0));
    assertEq(deployed.STATIC_CURVE_POLICY_SENTINEL(), address(1));
  }

  // ============ computeFee ============
  //
  // computeFee
  // ├── given a ruleset is set for the hook of the pool
  // │   ├── when the ruleset reverts
  // │   │   └── it reverts with the error of the ruleset
  // │   ├── when the ruleset returns a fee above MAX_PROTOCOL_FEE
  // │   │   └── it reverts with InvalidFeeValue
  // │   └── when the ruleset returns a fee at or below MAX_PROTOCOL_FEE
  // │       ├── when the pool has no hook
  // │       │   └── it returns the fee of the ruleset at HOOKLESS_POLICY_SENTINEL
  // │       ├── when the static curve also applies to the pool
  // │       │   └── it returns the ruleset fee and does not call the static curve
  // │       └── when the hook also returns a fee
  // │           └── it returns the ruleset fee and does not call the hook
  // └── given no ruleset is set for the hook of the pool
  //     ├── given the pool has no hook
  //     │   └── it returns the default fee and does not call the static curve
  //     └── given the pool has a hook
  //         ├── given the static curve applies to the pool
  //         │   ├── when the static curve reverts
  //         │   │   └── it reverts with the error of the static curve
  //         │   ├── when the static curve returns a fee above MAX_PROTOCOL_FEE
  //         │   │   └── it reverts with InvalidFeeValue
  //         │   └── when the static curve returns a fee at or below MAX_PROTOCOL_FEE
  //         │       └── it returns the static curve fee and does not call the hook
  //         └── given the static curve does not apply to the pool
  //             ├── given the hook does not return a fee
  //             │   ├── when the hook has no code
  //             │   │   └── it returns the default fee
  //             │   ├── when the hook does not support ERC165
  //             │   │   └── it returns the default fee
  //             │   └── when the hook does not support the ruleset interface
  //             │       └── it returns the default fee
  //             └── given the hook returns a fee
  //                 ├── when the hook reverts
  //                 │   └── it reverts with the error of the hook
  //                 ├── when the hook returns a fee above MAX_PROTOCOL_FEE
  //                 │   └── it reverts with InvalidFeeValue
  //                 └── when the hook returns a fee at or below MAX_PROTOCOL_FEE
  //                     ├── when the hook has custom accounting
  //                     │   └── it returns the hook fee and does not call the static curve
  //                     ├── when the pool has a dynamic LP fee
  //                     │   └── it returns the hook fee and does not call the static curve
  //                     └── when no static curve is set
  //                         └── it returns the hook fee
  //
  // The static curve applies to a pool that has a hook without RETURNS_DELTA flags, a static LP
  // fee, and a ruleset at STATIC_CURVE_POLICY_SENTINEL. Tests that put code at a hook address
  // deploy all mocks first. Then they assume that the fuzzed hook address has no code. Thus,
  // vm.etch does not change the code of a deployed contract.

  function testFuzz_computeFee_RevertWhen_TheRulesetReverts(PoolKey memory key) public {
    // Given: a ruleset is set for the hook of the pool. The fuzzer selects the hook.
    // When: the ruleset reverts.
    MockProtocolFeeRuleset ruleset = new MockProtocolFeeRuleset({fee: 0, reverts: true});
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(address(key.hooks), ruleset);

    // Then: computeFee reverts with the error of the ruleset.
    vm.expectRevert(MockProtocolFeeRuleset.MockReverted.selector);
    policy.computeFee(key);
  }

  function testFuzz_computeFee_RevertWhen_TheRulesetReturnsAnInvalidFee(
    PoolKey memory key,
    uint24 rulesetFee
  ) public {
    // Given: a ruleset is set for the hook of the pool. The fuzzer selects the hook.
    // When: the ruleset returns a fee above MAX_PROTOCOL_FEE in one or two directions.
    vm.assume(!ProtocolFeeLibrary.isValidProtocolFee(rulesetFee));
    MockProtocolFeeRuleset ruleset = new MockProtocolFeeRuleset({fee: rulesetFee, reverts: false});
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(address(key.hooks), ruleset);

    // Then: computeFee reverts with InvalidFeeValue.
    vm.expectRevert(IV4FeePolicy.InvalidFeeValue.selector);
    policy.computeFee(key);
  }

  function testFuzz_computeFee_GivenARuleset_WhenThePoolHasNoHook(
    PoolKey memory key,
    uint24 rulesetFee,
    uint24 defaultFee
  ) public {
    // When: the pool has no hook.
    key.hooks = IHooks(address(0));

    // Given: a default fee.
    vm.prank(feeSetter);
    policy.setDefaultFee(_boundProtocolFee(defaultFee));

    // Given: a ruleset at HOOKLESS_POLICY_SENTINEL returns a fee at or below MAX_PROTOCOL_FEE.
    rulesetFee = _boundProtocolFee(rulesetFee);
    MockProtocolFeeRuleset ruleset = new MockProtocolFeeRuleset({fee: rulesetFee, reverts: false});
    address hooklessSentinel = policy.HOOKLESS_POLICY_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(hooklessSentinel, ruleset);

    // Then: computeFee returns the fee of the ruleset at HOOKLESS_POLICY_SENTINEL.
    vm.expectCall(address(ruleset), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)));
    assertEq(policy.computeFee(key), rulesetFee);
  }

  function testFuzz_computeFee_GivenARuleset_WhenTheStaticCurveAlsoApplies(
    PoolKey memory key,
    uint24 rulesetFee,
    uint24 curveFee
  ) public {
    // Given: a hook without RETURNS_DELTA flags, and a static LP fee.
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = uint24(bound(key.fee, 0, LPFeeLibrary.MAX_LP_FEE));

    // When: the static curve at STATIC_CURVE_POLICY_SENTINEL also applies to the pool.
    MockProtocolFeeRuleset staticCurve =
      new MockProtocolFeeRuleset({fee: _boundProtocolFee(curveFee), reverts: false});
    address staticCurveSentinel = policy.STATIC_CURVE_POLICY_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(staticCurveSentinel, staticCurve);

    // Given: a ruleset is set for the hook, and it returns a fee at or below MAX_PROTOCOL_FEE.
    rulesetFee = _boundProtocolFee(rulesetFee);
    MockProtocolFeeRuleset ruleset = new MockProtocolFeeRuleset({fee: rulesetFee, reverts: false});
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(address(key.hooks), ruleset);

    // Then: computeFee returns the ruleset fee and does not call the static curve.
    vm.expectCall(address(ruleset), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)));
    vm.expectCall(
      address(staticCurve), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)), 0
    );
    assertEq(policy.computeFee(key), rulesetFee);
  }

  function testFuzz_computeFee_GivenARuleset_WhenTheHookAlsoReturnsAFee(
    PoolKey memory key,
    uint24 rulesetFee,
    uint24 hookFee
  ) public {
    // Given: a ruleset that returns a fee at or below MAX_PROTOCOL_FEE.
    rulesetFee = _boundProtocolFee(rulesetFee);
    MockProtocolFeeRuleset ruleset = new MockProtocolFeeRuleset({fee: rulesetFee, reverts: false});

    // When: the hook has custom accounting, and it also returns a fee through ERC165.
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: _boundProtocolFee(hookFee), reverts: false, supportsERC165: true, supportsRuleset: true
    });
    key.hooks = IHooks(
      address(
        uint160(address(key.hooks)) | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
      )
    );
    vm.assume(address(key.hooks).code.length == 0);
    vm.etch(address(key.hooks), address(implementation).code);

    // Given: the ruleset is set for the hook.
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(address(key.hooks), ruleset);

    // Then: computeFee returns the ruleset fee and does not call the hook.
    vm.expectCall(address(ruleset), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)));
    vm.expectCall(
      address(key.hooks), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)), 0
    );
    assertEq(policy.computeFee(key), rulesetFee);
  }

  function testFuzz_computeFee_GivenNoRuleset_GivenThePoolHasNoHook(
    PoolKey memory key,
    uint24 curveFee,
    uint24 defaultFee
  ) public {
    // Given: the pool has no hook, and no ruleset is set at HOOKLESS_POLICY_SENTINEL.
    key.hooks = IHooks(address(0));

    // Given: a static curve is set at STATIC_CURVE_POLICY_SENTINEL.
    MockProtocolFeeRuleset staticCurve =
      new MockProtocolFeeRuleset({fee: _boundProtocolFee(curveFee), reverts: false});
    address staticCurveSentinel = policy.STATIC_CURVE_POLICY_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(staticCurveSentinel, staticCurve);

    // Given: a default fee.
    defaultFee = _boundProtocolFee(defaultFee);
    vm.prank(feeSetter);
    policy.setDefaultFee(defaultFee);

    // Then: computeFee returns the default fee and does not call the static curve.
    vm.expectCall(
      address(staticCurve), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)), 0
    );
    assertEq(policy.computeFee(key), defaultFee);
  }

  function testFuzz_computeFee_RevertWhen_TheStaticCurveReverts(PoolKey memory key) public {
    // Given: a hook without RETURNS_DELTA flags and without a ruleset, and a static LP fee.
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = uint24(bound(key.fee, 0, LPFeeLibrary.MAX_LP_FEE));

    // Given: a static curve is set at STATIC_CURVE_POLICY_SENTINEL.
    // When: the static curve reverts.
    MockProtocolFeeRuleset staticCurve = new MockProtocolFeeRuleset({fee: 0, reverts: true});
    address staticCurveSentinel = policy.STATIC_CURVE_POLICY_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(staticCurveSentinel, staticCurve);

    // Then: computeFee reverts with the error of the static curve.
    vm.expectRevert(MockProtocolFeeRuleset.MockReverted.selector);
    policy.computeFee(key);
  }

  function testFuzz_computeFee_RevertWhen_TheStaticCurveReturnsAnInvalidFee(
    PoolKey memory key,
    uint24 curveFee
  ) public {
    // Given: a hook without RETURNS_DELTA flags and without a ruleset, and a static LP fee.
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = uint24(bound(key.fee, 0, LPFeeLibrary.MAX_LP_FEE));

    // Given: a static curve is set at STATIC_CURVE_POLICY_SENTINEL.
    // When: the static curve returns a fee above MAX_PROTOCOL_FEE in one or two directions.
    vm.assume(!ProtocolFeeLibrary.isValidProtocolFee(curveFee));
    MockProtocolFeeRuleset staticCurve = new MockProtocolFeeRuleset({fee: curveFee, reverts: false});
    address staticCurveSentinel = policy.STATIC_CURVE_POLICY_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(staticCurveSentinel, staticCurve);

    // Then: computeFee reverts with InvalidFeeValue.
    vm.expectRevert(IV4FeePolicy.InvalidFeeValue.selector);
    policy.computeFee(key);
  }

  function testFuzz_computeFee_WhenTheStaticCurveReturnsAValidFee(
    PoolKey memory key,
    uint24 curveFee,
    uint24 hookFee
  ) public {
    // Given: a static curve at STATIC_CURVE_POLICY_SENTINEL.
    // When: the static curve returns a fee at or below MAX_PROTOCOL_FEE.
    curveFee = _boundProtocolFee(curveFee);
    MockProtocolFeeRuleset staticCurve = new MockProtocolFeeRuleset({fee: curveFee, reverts: false});
    address staticCurveSentinel = policy.STATIC_CURVE_POLICY_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(staticCurveSentinel, staticCurve);

    // Given: a hook without RETURNS_DELTA flags and without a ruleset, and a static LP fee. The
    // hook also returns a fee through ERC165.
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: _boundProtocolFee(hookFee), reverts: false, supportsERC165: true, supportsRuleset: true
    });
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = uint24(bound(key.fee, 0, LPFeeLibrary.MAX_LP_FEE));
    vm.assume(address(key.hooks).code.length == 0);
    vm.etch(address(key.hooks), address(implementation).code);

    // Then: computeFee returns the static curve fee and does not call the hook.
    vm.expectCall(address(staticCurve), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)));
    vm.expectCall(
      address(key.hooks), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)), 0
    );
    assertEq(policy.computeFee(key), curveFee);
  }

  function testFuzz_computeFee_WhenTheHookHasNoCode(PoolKey memory key, uint24 defaultFee) public {
    // Given: a hook without a ruleset. No static curve is set at STATIC_CURVE_POLICY_SENTINEL.
    // When: the hook has no code.
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    vm.assume(address(key.hooks).code.length == 0);

    // Given: a default fee.
    defaultFee = _boundProtocolFee(defaultFee);
    vm.prank(feeSetter);
    policy.setDefaultFee(defaultFee);

    // Then: computeFee returns the default fee.
    assertEq(policy.computeFee(key), defaultFee);
  }

  function testFuzz_computeFee_WhenTheHookDoesNotSupportERC165(
    PoolKey memory key,
    uint24 hookFee,
    uint24 defaultFee
  ) public {
    // Given: a hook without a ruleset. No static curve is set at STATIC_CURVE_POLICY_SENTINEL.
    // When: the hook has getProtocolFee, but it returns false for the ERC165 interface ID.
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: _boundProtocolFee(hookFee), reverts: false, supportsERC165: false, supportsRuleset: true
    });
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    vm.assume(address(key.hooks).code.length == 0);
    vm.etch(address(key.hooks), address(implementation).code);

    // Given: a default fee.
    defaultFee = _boundProtocolFee(defaultFee);
    vm.prank(feeSetter);
    policy.setDefaultFee(defaultFee);

    // Then: computeFee returns the default fee.
    vm.expectCall(
      address(key.hooks), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)), 0
    );
    assertEq(policy.computeFee(key), defaultFee);
  }

  function testFuzz_computeFee_WhenTheHookDoesNotSupportTheRulesetInterface(
    PoolKey memory key,
    uint24 hookFee,
    uint24 defaultFee
  ) public {
    // Given: a hook without a ruleset. No static curve is set at STATIC_CURVE_POLICY_SENTINEL.
    // When: the hook supports ERC165, but it returns false for the ruleset interface ID.
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: _boundProtocolFee(hookFee), reverts: false, supportsERC165: true, supportsRuleset: false
    });
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    vm.assume(address(key.hooks).code.length == 0);
    vm.etch(address(key.hooks), address(implementation).code);

    // Given: a default fee.
    defaultFee = _boundProtocolFee(defaultFee);
    vm.prank(feeSetter);
    policy.setDefaultFee(defaultFee);

    // Then: computeFee returns the default fee.
    vm.expectCall(
      address(key.hooks), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)), 0
    );
    assertEq(policy.computeFee(key), defaultFee);
  }

  function testFuzz_computeFee_RevertWhen_TheHookReverts(PoolKey memory key) public {
    // Given: a hook without a ruleset. The hook returns a fee through ERC165. No static curve is
    // set at STATIC_CURVE_POLICY_SENTINEL.
    // When: the hook reverts.
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: 0, reverts: true, supportsERC165: true, supportsRuleset: true
    });
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    vm.assume(address(key.hooks).code.length == 0);
    vm.etch(address(key.hooks), address(implementation).code);

    // Then: computeFee reverts with the error of the hook.
    vm.expectRevert(MockProtocolFeeRuleset.MockReverted.selector);
    policy.computeFee(key);
  }

  function testFuzz_computeFee_RevertWhen_TheHookReturnsAnInvalidFee(
    PoolKey memory key,
    uint24 hookFee
  ) public {
    // Given: a hook without a ruleset. The hook returns a fee through ERC165. No static curve is
    // set at STATIC_CURVE_POLICY_SENTINEL.
    // When: the hook returns a fee above MAX_PROTOCOL_FEE in one or two directions.
    vm.assume(!ProtocolFeeLibrary.isValidProtocolFee(hookFee));
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: hookFee, reverts: false, supportsERC165: true, supportsRuleset: true
    });
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    vm.assume(address(key.hooks).code.length == 0);
    vm.etch(address(key.hooks), address(implementation).code);

    // Then: computeFee reverts with InvalidFeeValue.
    vm.expectRevert(IV4FeePolicy.InvalidFeeValue.selector);
    policy.computeFee(key);
  }

  function testFuzz_computeFee_WhenTheHookHasCustomAccounting(
    PoolKey memory key,
    uint256 returnsDeltaFlagIndex,
    uint24 hookFee,
    uint24 curveFee
  ) public {
    // Given: a static curve at STATIC_CURVE_POLICY_SENTINEL.
    MockProtocolFeeRuleset staticCurve =
      new MockProtocolFeeRuleset({fee: _boundProtocolFee(curveFee), reverts: false});
    address staticCurveSentinel = policy.STATIC_CURVE_POLICY_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(staticCurveSentinel, staticCurve);

    // Given: a hook without a ruleset, which returns a fee at or below MAX_PROTOCOL_FEE through
    // ERC165.
    // When: the hook has custom accounting: one RETURNS_DELTA flag and a static LP fee.
    hookFee = _boundProtocolFee(hookFee);
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: hookFee, reverts: false, supportsERC165: true, supportsRuleset: true
    });
    uint160 returnsDeltaFlag = uint160(1) << bound(returnsDeltaFlagIndex, 0, 3);
    key.hooks = IHooks(
      address(
        (uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG
          | returnsDeltaFlag
      )
    );
    key.fee = uint24(bound(key.fee, 0, LPFeeLibrary.MAX_LP_FEE));
    vm.assume(address(key.hooks).code.length == 0);
    vm.etch(address(key.hooks), address(implementation).code);

    // Then: computeFee returns the hook fee and does not call the static curve.
    vm.expectCall(address(key.hooks), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)));
    vm.expectCall(
      address(staticCurve), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)), 0
    );
    assertEq(policy.computeFee(key), hookFee);
  }

  function testFuzz_computeFee_WhenThePoolHasADynamicLPFee(
    PoolKey memory key,
    uint24 hookFee,
    uint24 curveFee
  ) public {
    // Given: a static curve at STATIC_CURVE_POLICY_SENTINEL.
    MockProtocolFeeRuleset staticCurve =
      new MockProtocolFeeRuleset({fee: _boundProtocolFee(curveFee), reverts: false});
    address staticCurveSentinel = policy.STATIC_CURVE_POLICY_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(staticCurveSentinel, staticCurve);

    // Given: a hook without RETURNS_DELTA flags and without a ruleset, which returns a fee at or
    // below MAX_PROTOCOL_FEE through ERC165.
    // When: the pool has a dynamic LP fee.
    hookFee = _boundProtocolFee(hookFee);
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: hookFee, reverts: false, supportsERC165: true, supportsRuleset: true
    });
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = LPFeeLibrary.DYNAMIC_FEE_FLAG;
    vm.assume(address(key.hooks).code.length == 0);
    vm.etch(address(key.hooks), address(implementation).code);

    // Then: computeFee returns the hook fee and does not call the static curve.
    vm.expectCall(address(key.hooks), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)));
    vm.expectCall(
      address(staticCurve), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)), 0
    );
    assertEq(policy.computeFee(key), hookFee);
  }

  function testFuzz_computeFee_WhenNoStaticCurveIsSet(PoolKey memory key, uint24 hookFee) public {
    // Given: a hook without RETURNS_DELTA flags and without a ruleset, and a static LP fee. The
    // hook returns a fee at or below MAX_PROTOCOL_FEE through ERC165.
    // When: no static curve is set at STATIC_CURVE_POLICY_SENTINEL.
    hookFee = _boundProtocolFee(hookFee);
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: hookFee, reverts: false, supportsERC165: true, supportsRuleset: true
    });
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = uint24(bound(key.fee, 0, LPFeeLibrary.MAX_LP_FEE));
    vm.assume(address(key.hooks).code.length == 0);
    vm.etch(address(key.hooks), address(implementation).code);

    // Then: computeFee returns the hook fee.
    vm.expectCall(address(key.hooks), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)));
    assertEq(policy.computeFee(key), hookFee);
  }

  // ============ setProtocolFeeRuleset ============
  //
  // setProtocolFeeRuleset
  // ├── when the caller is not the fee setter
  // │   └── it reverts with Unauthorized
  // └── when the caller is the fee setter
  //     ├── it replaces the ruleset of the hook
  //     └── it emits ProtocolFeeRulesetChanged

  function testFuzz_setProtocolFeeRuleset_RevertWhen_CallerIsNotTheFeeSetter(
    address caller,
    address hook,
    IV4ProtocolFeeRuleset ruleset
  ) public {
    // When: the caller is not the fee setter.
    vm.assume(caller != feeSetter);

    // Then: setProtocolFeeRuleset reverts with Unauthorized.
    vm.prank(caller);
    vm.expectRevert(IV4FeePolicy.Unauthorized.selector);
    policy.setProtocolFeeRuleset(hook, ruleset);
  }

  function testFuzz_setProtocolFeeRuleset_WhenCallerIsTheFeeSetter(
    address hook,
    IV4ProtocolFeeRuleset previousRuleset,
    IV4ProtocolFeeRuleset ruleset
  ) public {
    // Given: a ruleset is set for the hook.
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(hook, previousRuleset);

    // When: the caller is the fee setter.
    // Then: setProtocolFeeRuleset emits ProtocolFeeRulesetChanged.
    vm.expectEmit(address(policy));
    emit IV4FeePolicy.ProtocolFeeRulesetChanged(hook, ruleset);
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(hook, ruleset);

    // Then: setProtocolFeeRuleset replaces the ruleset of the hook.
    assertEq(address(policy.rulesets(hook)), address(ruleset));
  }

  // ============ batchSetProtocolFeeRulesets ============
  //
  // batchSetProtocolFeeRulesets
  // ├── when the caller is not the fee setter
  // │   └── it reverts with Unauthorized
  // └── when the caller is the fee setter
  //     ├── when there are no assignments
  //     │   └── it does not emit and does not change a ruleset
  //     └── when there are assignments
  //         ├── it sets the ruleset of each hook
  //         ├── it emits ProtocolFeeRulesetChanged for each assignment, in sequence
  //         └── when two assignments have the same hook
  //             └── it keeps the last ruleset

  function testFuzz_batchSetProtocolFeeRulesets_RevertWhen_CallerIsNotTheFeeSetter(
    address caller,
    ProtocolFeeRulesetAssignment[] memory assignments
  ) public {
    // When: the caller is not the fee setter.
    vm.assume(caller != feeSetter);

    // Then: batchSetProtocolFeeRulesets reverts with Unauthorized.
    vm.prank(caller);
    vm.expectRevert(IV4FeePolicy.Unauthorized.selector);
    policy.batchSetProtocolFeeRulesets(assignments);
  }

  function testFuzz_batchSetProtocolFeeRulesets_WhenThereAreNoAssignments(
    address hook,
    IV4ProtocolFeeRuleset ruleset
  ) public {
    // Given: a ruleset is set for a hook.
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(hook, ruleset);

    // When: the caller is the fee setter, and there are no assignments.
    vm.recordLogs();
    vm.prank(feeSetter);
    policy.batchSetProtocolFeeRulesets(new ProtocolFeeRulesetAssignment[](0));

    // Then: batchSetProtocolFeeRulesets does not emit and does not change a ruleset.
    assertEq(vm.getRecordedLogs().length, 0);
    assertEq(address(policy.rulesets(hook)), address(ruleset));
  }

  function testFuzz_batchSetProtocolFeeRulesets_WhenThereAreAssignments(
    bytes32 hookSeed,
    IV4ProtocolFeeRuleset[8] memory newRulesets,
    uint256 count
  ) public {
    // When: the caller is the fee setter, and there are 1 to 8 assignments to different hooks.
    count = bound(count, 1, 8);
    ProtocolFeeRulesetAssignment[] memory assignments = new ProtocolFeeRulesetAssignment[](count);
    for (uint256 i; i < count; ++i) {
      address hook = address(uint160(uint256(keccak256(abi.encode(hookSeed, i)))));
      assignments[i] = ProtocolFeeRulesetAssignment({hook: hook, ruleset: newRulesets[i]});
    }

    // Then: batchSetProtocolFeeRulesets emits ProtocolFeeRulesetChanged for each assignment, in
    // sequence.
    for (uint256 i; i < count; ++i) {
      vm.expectEmit(address(policy));
      emit IV4FeePolicy.ProtocolFeeRulesetChanged(assignments[i].hook, assignments[i].ruleset);
    }
    vm.prank(feeSetter);
    policy.batchSetProtocolFeeRulesets(assignments);

    // Then: batchSetProtocolFeeRulesets sets the ruleset of each hook.
    for (uint256 i; i < count; ++i) {
      assertEq(address(policy.rulesets(assignments[i].hook)), address(assignments[i].ruleset));
    }
  }

  function testFuzz_batchSetProtocolFeeRulesets_WhenTwoAssignmentsHaveTheSameHook(
    address hook,
    IV4ProtocolFeeRuleset firstRuleset,
    IV4ProtocolFeeRuleset lastRuleset
  ) public {
    // When: the caller is the fee setter, and two assignments have the same hook.
    ProtocolFeeRulesetAssignment[] memory assignments = new ProtocolFeeRulesetAssignment[](2);
    assignments[0] = ProtocolFeeRulesetAssignment({hook: hook, ruleset: firstRuleset});
    assignments[1] = ProtocolFeeRulesetAssignment({hook: hook, ruleset: lastRuleset});
    vm.prank(feeSetter);
    policy.batchSetProtocolFeeRulesets(assignments);

    // Then: batchSetProtocolFeeRulesets keeps the last ruleset.
    assertEq(address(policy.rulesets(hook)), address(lastRuleset));
  }

  // ============ setFeeSetter ============
  //
  // setFeeSetter
  // ├── when the caller is not the owner
  // │   └── it reverts with UNAUTHORIZED
  // └── when the caller is the owner
  //     ├── it sets the fee setter
  //     └── it emits FeeSetterUpdated

  function testFuzz_setFeeSetter_RevertWhen_CallerIsNotTheOwner(
    address caller,
    address newFeeSetter
  ) public {
    // When: the caller is not the owner.
    vm.assume(caller != owner);

    // Then: setFeeSetter reverts with UNAUTHORIZED.
    vm.prank(caller);
    vm.expectRevert("UNAUTHORIZED");
    policy.setFeeSetter(newFeeSetter);
  }

  function testFuzz_setFeeSetter_WhenCallerIsTheOwner(address newFeeSetter) public {
    // When: the caller is the owner.
    // Then: setFeeSetter emits FeeSetterUpdated.
    vm.expectEmit(address(policy));
    emit IV4FeePolicy.FeeSetterUpdated(feeSetter, newFeeSetter);
    vm.prank(owner);
    policy.setFeeSetter(newFeeSetter);

    // Then: setFeeSetter sets the fee setter.
    assertEq(policy.feeSetter(), newFeeSetter);
  }

  // ============ setDefaultFee ============
  //
  // setDefaultFee
  // ├── when the caller is not the fee setter
  // │   └── it reverts with Unauthorized
  // └── when the caller is the fee setter
  //     ├── when the fee is above MAX_PROTOCOL_FEE
  //     │   └── it reverts with InvalidFeeValue
  //     └── when the fee is at or below MAX_PROTOCOL_FEE
  //         ├── it sets the default fee
  //         └── it emits DefaultFeeUpdated with the previous fee and the new fee

  function testFuzz_setDefaultFee_RevertWhen_CallerIsNotTheFeeSetter(address caller, uint24 fee)
    public
  {
    // When: the caller is not the fee setter.
    vm.assume(caller != feeSetter);

    // Then: setDefaultFee reverts with Unauthorized.
    vm.prank(caller);
    vm.expectRevert(IV4FeePolicy.Unauthorized.selector);
    policy.setDefaultFee(fee);
  }

  function testFuzz_setDefaultFee_RevertWhen_TheFeeIsInvalid(uint24 fee) public {
    // When: the caller is the fee setter.
    // When: the fee is above MAX_PROTOCOL_FEE in one or two directions.
    vm.assume(!ProtocolFeeLibrary.isValidProtocolFee(fee));

    // Then: setDefaultFee reverts with InvalidFeeValue.
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeePolicy.InvalidFeeValue.selector);
    policy.setDefaultFee(fee);
  }

  function testFuzz_setDefaultFee_WhenTheFeeIsValid(uint24 previousFee, uint24 fee) public {
    // Given: a previous default fee.
    previousFee = _boundProtocolFee(previousFee);
    vm.prank(feeSetter);
    policy.setDefaultFee(previousFee);

    // When: the caller is the fee setter.
    // When: the fee is at or below MAX_PROTOCOL_FEE.
    fee = _boundProtocolFee(fee);

    // Then: setDefaultFee emits DefaultFeeUpdated with the previous fee and the new fee.
    vm.expectEmit(address(policy));
    emit IV4FeePolicy.DefaultFeeUpdated(previousFee, fee);
    vm.prank(feeSetter);
    policy.setDefaultFee(fee);

    // Then: setDefaultFee sets the default fee.
    assertEq(policy.defaultFee(), fee);
  }

  // ============ transferOwnership ============
  //
  // transferOwnership
  // ├── when the caller is not the owner
  // │   └── it reverts with UNAUTHORIZED
  // └── when the caller is the owner
  //     ├── it sets the owner
  //     └── it emits OwnershipTransferred

  function testFuzz_transferOwnership_RevertWhen_CallerIsNotTheOwner(
    address caller,
    address newOwner
  ) public {
    // When: the caller is not the owner.
    vm.assume(caller != owner);

    // Then: transferOwnership reverts with UNAUTHORIZED.
    vm.prank(caller);
    vm.expectRevert("UNAUTHORIZED");
    policy.transferOwnership(newOwner);
  }

  function testFuzz_transferOwnership_WhenCallerIsTheOwner(address newOwner) public {
    // When: the caller is the owner.
    // Then: transferOwnership emits OwnershipTransferred.
    vm.expectEmit(address(policy));
    emit Owned.OwnershipTransferred(owner, newOwner);
    vm.prank(owner);
    policy.transferOwnership(newOwner);

    // Then: transferOwnership sets the owner.
    assertEq(policy.owner(), newOwner);
  }
}
