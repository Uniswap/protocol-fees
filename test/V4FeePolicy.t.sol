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
import {
  MockGarbageHook,
  MockOutOfGasRuleset,
  MockProtocolFeeRuleset,
  MockRevertingHook,
  MockSelfReportingHook,
  MockShortReturnRuleset
} from "./mocks/MockProtocolFeeRuleset.sol";

/// @dev Each section starts with the branch tree of one function. The tests are in the same
/// sequence as the tree. Each test sets all conditions of its branch, thus setUp has no pool or
/// mock state.
contract V4FeePolicyTest is Test {
  /// @dev The four RETURNS_DELTA flags of v4-core. A hook with one or more of these flags does
  /// custom accounting.
  uint160 internal constant RETURNS_DELTA_FLAGS = Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
    | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG
    | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG;

  /// @dev The rulesets key of pools that have no hook.
  address internal constant NO_HOOK = address(0);

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

  /// @dev A static LP fee and a hook address that has no RETURNS_DELTA flags.
  function _staticHookedKey(address hook) internal pure returns (PoolKey memory key) {
    key.fee = 3000;
    key.tickSpacing = 60;
    key.hooks = IHooks(hook);
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
    assertEq(deployed.NATIVE_MATH_POOL_SENTINEL(), address(1));
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
  // │       │   ├── it returns the fee of the ruleset at address(0)
  // │       │   └── when that ruleset returns zero
  // │       │       └── it returns zero and does not fall through to the default fee
  // │       ├── when the static curve also applies to the pool
  // │       │   └── it returns the ruleset fee and does not call the static curve
  // │       ├── when the static curve and the hook also apply
  // │       │   └── it returns the ruleset fee and does not call the static curve or the
  // hook
  // │       └── when the hook also returns a fee
  // │           └── it returns the ruleset fee and does not call the hook
  // └── given no ruleset is set for the hook of the pool
  //     ├── given the pool has no hook
  //     │   ├── when a static curve is set
  //     │   │   └── it returns the default fee and does not call the static curve
  //     │   ├── when no static curve is set
  //     │   │   └── it returns the default fee
  //     │   └── when the default fee is zero
  //     │       └── it returns zero
  //     └── given the pool has a hook
  //         ├── given the hook has no custom accounting and the LP fee is static
  //         │   ├── when a static curve is set at NATIVE_MATH_POOL_SENTINEL
  //         │   │   ├── when the static curve reverts
  //         │   │   │   └── it reverts with the error of the static curve
  //         │   │   ├── when the static curve runs out of gas
  //         │   │   │   └── it reverts and does not fall through
  //         │   │   ├── when the static curve returns short data
  //         │   │   │   └── it reverts and does not fall through
  //         │   │   ├── when the static curve returns a fee above MAX_PROTOCOL_FEE
  //         │   │   │   └── it reverts with InvalidFeeValue
  //         │   │   ├── when the static curve returns a nonzero fee
  //         │   │   │   └── it returns the static curve fee and does not call the hook
  //         │   │   └── when the static curve returns zero
  //         │   │       └── it returns zero and does not fall through
  //         │   └── when no static curve is set
  //         │       ├── when the hook returns a fee
  //         │       │   ├── when the hook reverts
  //         │       │   │   └── it reverts with the error of the hook
  //         │       │   ├── when the hook returns a fee above MAX_PROTOCOL_FEE
  //         │       │   │   └── it reverts with InvalidFeeValue
  //         │       │   └── when the hook returns a fee at or below MAX_PROTOCOL_FEE
  //         │       │       └── it returns the hook fee
  //         │       └── when the hook does not return a fee
  //         │           ├── when the hook does not support the ruleset interface
  //         │           │   └── it returns the default fee
  //         │           ├── when supportsInterface reverts
  //         │           │   └── it returns the default fee
  //         │           └── when supportsInterface returns a garbage word for every id
  //         │               └── it returns the default fee
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
  //                     └── when the pool has a dynamic LP fee
  //                         └── it returns the hook fee and does not call the static curve
  //
  // A hook without RETURNS_DELTA flags and a static LP fee uses the static curve when a ruleset is
  // set at NATIVE_MATH_POOL_SENTINEL. With no ruleset there, computeFee continues to hook
  // opt-in, then the default fee. A configured static curve that returns zero does not fall
  // through. Hookless pools use the address(0) ruleset if it is set, and defaultFee if it is not.
  // They cannot opt in. Custom accounting and a dynamic LP fee skip the static curve. Tests that
  // put code at a hook address deploy all mocks first. Then they assume that the fuzzed hook
  // address has no
  // code. Thus, vm.etch does not change the code of a deployed contract.

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

    // Given: a ruleset at address(0) returns a fee at or below MAX_PROTOCOL_FEE.
    rulesetFee = _boundProtocolFee(rulesetFee);
    MockProtocolFeeRuleset ruleset = new MockProtocolFeeRuleset({fee: rulesetFee, reverts: false});
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(NO_HOOK, ruleset);

    // Then: computeFee returns the fee of the ruleset at address(0).
    vm.expectCall(address(ruleset), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)));
    assertEq(policy.computeFee(key), rulesetFee);
  }

  function testFuzz_computeFee_GivenARuleset_WhenThePoolHasNoHook_WhenTheRulesetReturnsZero(
    PoolKey memory key,
    uint24 defaultFee
  ) public {
    // Given: the pool has no hook. The address(0) ruleset returns zero, and the default fee is not
    // zero. A configured zero does not fall through.
    key.hooks = IHooks(address(0));
    defaultFee = _boundProtocolFee(defaultFee);
    vm.assume(defaultFee != 0);
    MockProtocolFeeRuleset ruleset = new MockProtocolFeeRuleset({fee: 0, reverts: false});
    vm.startPrank(feeSetter);
    policy.setDefaultFee(defaultFee);
    policy.setProtocolFeeRuleset(NO_HOOK, ruleset);
    vm.stopPrank();

    // Then: computeFee returns zero and does not use the default fee.
    vm.expectCall(address(ruleset), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)));
    assertEq(policy.computeFee(key), 0);
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

    // When: the static curve at NATIVE_MATH_POOL_SENTINEL also applies to the pool.
    MockProtocolFeeRuleset staticCurve =
      new MockProtocolFeeRuleset({fee: _boundProtocolFee(curveFee), reverts: false});
    address nativeMathPoolSentinel = policy.NATIVE_MATH_POOL_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(nativeMathPoolSentinel, staticCurve);

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

  function testFuzz_computeFee_GivenARuleset_WhenTheStaticCurveAndTheHookAlsoApply(
    PoolKey memory key,
    uint24 rulesetFee,
    uint24 curveFee,
    uint24 hookFee,
    uint24 defaultFee
  ) public {
    // Given: a static LP fee and a hook without RETURNS_DELTA flags that also returns a fee.
    rulesetFee = _boundProtocolFee(rulesetFee);
    curveFee = _boundProtocolFee(curveFee);
    hookFee = _boundProtocolFee(hookFee);
    defaultFee = _boundProtocolFee(defaultFee);
    vm.assume(rulesetFee != curveFee && rulesetFee != hookFee && rulesetFee != defaultFee);
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: hookFee, reverts: false, supportsERC165: true, supportsRuleset: true
    });
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = uint24(bound(key.fee, 0, LPFeeLibrary.MAX_LP_FEE));
    vm.assume(address(key.hooks).code.length == 0);
    vm.etch(address(key.hooks), address(implementation).code);

    // Given: a static curve, a default fee, and a ruleset assigned to the hook.
    MockProtocolFeeRuleset staticCurve = new MockProtocolFeeRuleset({fee: curveFee, reverts: false});
    MockProtocolFeeRuleset ruleset = new MockProtocolFeeRuleset({fee: rulesetFee, reverts: false});
    address nativeMathPoolSentinel = policy.NATIVE_MATH_POOL_SENTINEL();
    vm.startPrank(feeSetter);
    policy.setProtocolFeeRuleset(nativeMathPoolSentinel, staticCurve);
    policy.setProtocolFeeRuleset(address(key.hooks), ruleset);
    policy.setDefaultFee(defaultFee);
    vm.stopPrank();

    // Then: computeFee returns the assigned ruleset and does not call the static curve or the hook.
    vm.expectCall(address(ruleset), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)));
    vm.expectCall(
      address(staticCurve), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)), 0
    );
    vm.expectCall(
      address(key.hooks), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)), 0
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
    // Given: the pool has no hook, and no ruleset is set at address(0).
    key.hooks = IHooks(address(0));

    // Given: a static curve is set at NATIVE_MATH_POOL_SENTINEL.
    MockProtocolFeeRuleset staticCurve =
      new MockProtocolFeeRuleset({fee: _boundProtocolFee(curveFee), reverts: false});
    address nativeMathPoolSentinel = policy.NATIVE_MATH_POOL_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(nativeMathPoolSentinel, staticCurve);

    // Given: a default fee other than zero.
    defaultFee = _boundProtocolFee(defaultFee);
    vm.assume(defaultFee != 0);
    vm.prank(feeSetter);
    policy.setDefaultFee(defaultFee);

    // Then: computeFee returns the default fee and does not call the static curve.
    vm.expectCall(
      address(staticCurve), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)), 0
    );
    assertEq(policy.computeFee(key), defaultFee);
  }

  function testFuzz_computeFee_GivenNoRuleset_GivenThePoolHasNoHook_WhenNoStaticCurveIsSet(
    PoolKey memory key,
    uint24 defaultFee
  ) public {
    // Given: the pool has no hook, and no ruleset is set at address(0).
    // When: no static curve is set at NATIVE_MATH_POOL_SENTINEL.
    key.hooks = IHooks(address(0));

    // Given: a default fee other than zero.
    defaultFee = _boundProtocolFee(defaultFee);
    vm.assume(defaultFee != 0);
    vm.prank(feeSetter);
    policy.setDefaultFee(defaultFee);

    // Then: computeFee returns the default fee. Hookless pools cannot opt in.
    assertEq(policy.computeFee(key), defaultFee);
    assertEq(address(policy.rulesets(NO_HOOK)), address(0));
  }

  function testFuzz_computeFee_GivenNoRuleset_GivenThePoolHasNoHook_WhenDefaultFeeIsZero(PoolKey memory key)
    public
  {
    // Given: the pool has no hook, address(0) is unset, and the default fee is zero.
    key.hooks = IHooks(address(0));
    assertEq(policy.defaultFee(), 0);
    assertEq(address(policy.rulesets(NO_HOOK)), address(0));

    // Then: computeFee returns zero.
    assertEq(policy.computeFee(key), 0);
  }

  function testFuzz_computeFee_RevertWhen_TheStaticCurveReverts(PoolKey memory key) public {
    // Given: a hook without RETURNS_DELTA flags and without a ruleset, and a static LP fee.
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = uint24(bound(key.fee, 0, LPFeeLibrary.MAX_LP_FEE));

    // Given: a static curve is set at NATIVE_MATH_POOL_SENTINEL.
    // When: the static curve reverts.
    MockProtocolFeeRuleset staticCurve = new MockProtocolFeeRuleset({fee: 0, reverts: true});
    address nativeMathPoolSentinel = policy.NATIVE_MATH_POOL_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(nativeMathPoolSentinel, staticCurve);

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

    // Given: a static curve is set at NATIVE_MATH_POOL_SENTINEL.
    // When: the static curve returns a fee above MAX_PROTOCOL_FEE in one or two directions.
    vm.assume(!ProtocolFeeLibrary.isValidProtocolFee(curveFee));
    MockProtocolFeeRuleset staticCurve = new MockProtocolFeeRuleset({fee: curveFee, reverts: false});
    address nativeMathPoolSentinel = policy.NATIVE_MATH_POOL_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(nativeMathPoolSentinel, staticCurve);

    // Then: computeFee reverts with InvalidFeeValue. A curve that runs out of gas or returns
    // short data also fails the call, below, and does not fall through to the hook or defaultFee.
    vm.expectRevert(IV4FeePolicy.InvalidFeeValue.selector);
    policy.computeFee(key);
  }

  function test_computeFee_RevertWhen_TheStaticCurveRunsOutOfGas() public {
    // Given: a static curve that burns the gas of getProtocolFee. The hook has opted in and would
    // return a fee, and the default fee is set. Neither is used when the curve call fails.
    uint24 hookFee = 200 << 12 | 200;
    uint24 defaultFee = 100 << 12 | 100;
    MockOutOfGasRuleset staticCurve = new MockOutOfGasRuleset();
    address nativeMathPoolSentinel = policy.NATIVE_MATH_POOL_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(
      nativeMathPoolSentinel, IV4ProtocolFeeRuleset(address(staticCurve))
    );
    vm.prank(feeSetter);
    policy.setDefaultFee(defaultFee);

    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: hookFee, reverts: false, supportsERC165: true, supportsRuleset: true
    });
    PoolKey memory key = _staticHookedKey(address(uint160(Hooks.BEFORE_SWAP_FLAG)));
    vm.etch(address(key.hooks), address(implementation).code);

    // Then: computeFee reverts. It does not return the hook fee or the default fee.
    vm.expectCall(
      address(key.hooks), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)), 0
    );
    vm.expectRevert();
    policy.computeFee(key);
  }

  function test_computeFee_RevertWhen_TheStaticCurveReturnsShortData() public {
    // Given: a static curve that returns fewer than 32 bytes from getProtocolFee. The hook has
    // opted in and would return a fee, and the default fee is set.
    uint24 hookFee = 200 << 12 | 200;
    uint24 defaultFee = 100 << 12 | 100;
    MockShortReturnRuleset staticCurve = new MockShortReturnRuleset();
    address nativeMathPoolSentinel = policy.NATIVE_MATH_POOL_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(
      nativeMathPoolSentinel, IV4ProtocolFeeRuleset(address(staticCurve))
    );
    vm.prank(feeSetter);
    policy.setDefaultFee(defaultFee);

    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: hookFee, reverts: false, supportsERC165: true, supportsRuleset: true
    });
    PoolKey memory key = _staticHookedKey(address(uint160(Hooks.AFTER_SWAP_FLAG)));
    vm.etch(address(key.hooks), address(implementation).code);

    // Then: the ABI decode reverts computeFee, the same as an invalid fee in that the call fails
    // and does not fall through to the hook or the default fee.
    vm.expectCall(
      address(key.hooks), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)), 0
    );
    vm.expectRevert();
    policy.computeFee(key);
  }

  function testFuzz_computeFee_WhenTheStaticCurveReturnsAValidFee(
    PoolKey memory key,
    uint24 curveFee,
    uint24 hookFee
  ) public {
    // Given: a static curve at NATIVE_MATH_POOL_SENTINEL.
    // When: the static curve returns a nonzero fee at or below MAX_PROTOCOL_FEE.
    curveFee = _boundProtocolFee(curveFee);
    vm.assume(curveFee != 0);
    MockProtocolFeeRuleset staticCurve = new MockProtocolFeeRuleset({fee: curveFee, reverts: false});
    address nativeMathPoolSentinel = policy.NATIVE_MATH_POOL_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(nativeMathPoolSentinel, staticCurve);

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

  function testFuzz_computeFee_WhenTheStaticCurveReturnsZero(
    PoolKey memory key,
    uint24 hookFee,
    uint24 defaultFee
  ) public {
    // Given: a static curve at NATIVE_MATH_POOL_SENTINEL that returns zero. Zero from a
    // configured curve is deliberate.
    MockProtocolFeeRuleset staticCurve = new MockProtocolFeeRuleset({fee: 0, reverts: false});
    address nativeMathPoolSentinel = policy.NATIVE_MATH_POOL_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(nativeMathPoolSentinel, staticCurve);

    // Given: a hook without RETURNS_DELTA flags and without a ruleset, and a static LP fee. The
    // hook would return a nonzero fee, and the default fee is also nonzero.
    hookFee = _boundProtocolFee(hookFee);
    defaultFee = _boundProtocolFee(defaultFee);
    vm.assume(hookFee != 0 && defaultFee != 0);
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: hookFee, reverts: false, supportsERC165: true, supportsRuleset: true
    });
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = uint24(bound(key.fee, 0, LPFeeLibrary.MAX_LP_FEE));
    vm.assume(address(key.hooks).code.length == 0);
    vm.etch(address(key.hooks), address(implementation).code);
    vm.prank(feeSetter);
    policy.setDefaultFee(defaultFee);

    // Then: computeFee returns zero and does not call the hook or use the default fee.
    vm.expectCall(address(staticCurve), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)));
    vm.expectCall(
      address(key.hooks), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)), 0
    );
    assertEq(policy.computeFee(key), 0);
  }

  function testFuzz_computeFee_WhenNoStaticCurveIsSet_WhenTheHookReturnsAFee(
    PoolKey memory key,
    uint24 hookFee,
    uint24 defaultFee
  ) public {
    // Given: a hook without RETURNS_DELTA flags and without a ruleset, and a static LP fee.
    // When: no static curve is set, and the hook returns a fee through ERC165.
    hookFee = _boundProtocolFee(hookFee);
    defaultFee = _boundProtocolFee(defaultFee);
    vm.assume(hookFee != defaultFee);
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: hookFee, reverts: false, supportsERC165: true, supportsRuleset: true
    });
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = uint24(bound(key.fee, 0, LPFeeLibrary.MAX_LP_FEE));
    vm.assume(address(key.hooks).code.length == 0);
    vm.etch(address(key.hooks), address(implementation).code);
    vm.prank(feeSetter);
    policy.setDefaultFee(defaultFee);

    // Then: computeFee returns the hook fee.
    vm.expectCall(address(key.hooks), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)));
    assertEq(policy.computeFee(key), hookFee);
  }

  function testFuzz_computeFee_WhenNoStaticCurveIsSet_RevertWhen_TheHookReverts(PoolKey memory key)
    public
  {
    // Given: a hook without RETURNS_DELTA flags and without a ruleset, and a static LP fee.
    // When: no static curve is set, and the opted-in hook reverts.
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: 0, reverts: true, supportsERC165: true, supportsRuleset: true
    });
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = uint24(bound(key.fee, 0, LPFeeLibrary.MAX_LP_FEE));
    vm.assume(address(key.hooks).code.length == 0);
    vm.etch(address(key.hooks), address(implementation).code);

    // Then: computeFee reverts with the error of the hook.
    vm.expectRevert(MockProtocolFeeRuleset.MockReverted.selector);
    policy.computeFee(key);
  }

  function testFuzz_computeFee_WhenNoStaticCurveIsSet_RevertWhen_TheHookReturnsAnInvalidFee(
    PoolKey memory key,
    uint24 hookFee
  ) public {
    // Given: a hook without RETURNS_DELTA flags and without a ruleset, and a static LP fee.
    // When: no static curve is set, and the hook returns a fee above MAX_PROTOCOL_FEE.
    vm.assume(!ProtocolFeeLibrary.isValidProtocolFee(hookFee));
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: hookFee, reverts: false, supportsERC165: true, supportsRuleset: true
    });
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = uint24(bound(key.fee, 0, LPFeeLibrary.MAX_LP_FEE));
    vm.assume(address(key.hooks).code.length == 0);
    vm.etch(address(key.hooks), address(implementation).code);

    // Then: computeFee reverts with InvalidFeeValue.
    vm.expectRevert(IV4FeePolicy.InvalidFeeValue.selector);
    policy.computeFee(key);
  }

  function testFuzz_computeFee_WhenNoStaticCurveIsSet_WhenTheHookDoesNotSupportTheRulesetInterface(
    PoolKey memory key,
    uint24 hookFee,
    uint24 defaultFee
  ) public {
    // Given: a hook without RETURNS_DELTA flags and without a ruleset, and a static LP fee.
    // When: no static curve is set, and the hook supports ERC165 but not the ruleset interface.
    defaultFee = _boundProtocolFee(defaultFee);
    vm.assume(defaultFee != 0);
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: _boundProtocolFee(hookFee), reverts: false, supportsERC165: true, supportsRuleset: false
    });
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = uint24(bound(key.fee, 0, LPFeeLibrary.MAX_LP_FEE));
    vm.assume(address(key.hooks).code.length == 0);
    vm.etch(address(key.hooks), address(implementation).code);
    vm.prank(feeSetter);
    policy.setDefaultFee(defaultFee);

    // Then: computeFee returns the default fee and does not call the hook.
    vm.expectCall(
      address(key.hooks), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)), 0
    );
    assertEq(policy.computeFee(key), defaultFee);
  }

  function testFuzz_computeFee_WhenNoStaticCurveIsSet_WhenSupportsInterfaceReverts(
    PoolKey memory key,
    uint24 defaultFee
  ) public {
    // Given: a hook without RETURNS_DELTA flags and without a ruleset, and a static LP fee.
    // When: no static curve is set, and supportsInterface reverts.
    defaultFee = _boundProtocolFee(defaultFee);
    vm.assume(defaultFee != 0);
    MockRevertingHook implementation = new MockRevertingHook();
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = uint24(bound(key.fee, 0, LPFeeLibrary.MAX_LP_FEE));
    vm.assume(address(key.hooks).code.length == 0);
    vm.etch(address(key.hooks), address(implementation).code);
    vm.prank(feeSetter);
    policy.setDefaultFee(defaultFee);

    // Then: ERC165Checker treats the revert as "not supported", and computeFee returns the default.
    vm.expectCall(
      address(key.hooks), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)), 0
    );
    assertEq(policy.computeFee(key), defaultFee);
  }

  function testFuzz_computeFee_WhenNoStaticCurveIsSet_WhenSupportsInterfaceReturnsGarbage(
    PoolKey memory key,
    uint24 defaultFee,
    uint256 word
  ) public {
    // Given: a hook without RETURNS_DELTA flags and without a ruleset, and a static LP fee.
    // When: no static curve is set, and every supportsInterface query returns the same nonzero
    // word. That word also claims the invalid interface id, so the hook has not opted in.
    word = bound(word, 1, type(uint256).max);
    defaultFee = _boundProtocolFee(defaultFee);
    vm.assume(defaultFee != 0);
    MockGarbageHook implementation = new MockGarbageHook(word);
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = uint24(bound(key.fee, 0, LPFeeLibrary.MAX_LP_FEE));
    vm.assume(address(key.hooks).code.length == 0);
    vm.etch(address(key.hooks), address(implementation).code);
    vm.prank(feeSetter);
    policy.setDefaultFee(defaultFee);

    // Then: computeFee returns the default fee and does not call getProtocolFee.
    vm.expectCall(
      address(key.hooks), abi.encodeCall(IV4ProtocolFeeRuleset.getProtocolFee, (key)), 0
    );
    assertEq(policy.computeFee(key), defaultFee);
  }

  function testFuzz_computeFee_WhenTheHookHasNoCode(PoolKey memory key, uint24 defaultFee) public {
    // Given: a hook without a ruleset. The pool has a dynamic LP fee, so the static curve does
    // not apply.
    // When: the hook has no code.
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = LPFeeLibrary.DYNAMIC_FEE_FLAG;
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
    // Given: a hook without a ruleset. The pool has a dynamic LP fee, so the static curve does
    // not apply.
    // When: the hook has getProtocolFee, but it returns false for the ERC165 interface ID.
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: _boundProtocolFee(hookFee), reverts: false, supportsERC165: false, supportsRuleset: true
    });
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = LPFeeLibrary.DYNAMIC_FEE_FLAG;
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
    // Given: a hook without a ruleset. The pool has a dynamic LP fee, so the static curve does
    // not apply.
    // When: the hook supports ERC165, but it returns false for the ruleset interface ID.
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: _boundProtocolFee(hookFee), reverts: false, supportsERC165: true, supportsRuleset: false
    });
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = LPFeeLibrary.DYNAMIC_FEE_FLAG;
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
    // Given: a hook without a ruleset. The hook returns a fee through ERC165. The pool has a
    // dynamic LP fee, so the static curve does not apply.
    // When: the hook reverts.
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: 0, reverts: true, supportsERC165: true, supportsRuleset: true
    });
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = LPFeeLibrary.DYNAMIC_FEE_FLAG;
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
    // Given: a hook without a ruleset. The hook returns a fee through ERC165. The pool has a
    // dynamic LP fee, so the static curve does not apply.
    // When: the hook returns a fee above MAX_PROTOCOL_FEE in one or two directions.
    vm.assume(!ProtocolFeeLibrary.isValidProtocolFee(hookFee));
    MockSelfReportingHook implementation = new MockSelfReportingHook({
      fee: hookFee, reverts: false, supportsERC165: true, supportsRuleset: true
    });
    key.hooks = IHooks(
      address((uint160(address(key.hooks)) & ~RETURNS_DELTA_FLAGS) | Hooks.BEFORE_SWAP_FLAG)
    );
    key.fee = LPFeeLibrary.DYNAMIC_FEE_FLAG;
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
    // Given: a static curve at NATIVE_MATH_POOL_SENTINEL.
    MockProtocolFeeRuleset staticCurve =
      new MockProtocolFeeRuleset({fee: _boundProtocolFee(curveFee), reverts: false});
    address nativeMathPoolSentinel = policy.NATIVE_MATH_POOL_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(nativeMathPoolSentinel, staticCurve);

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
    // Given: a static curve at NATIVE_MATH_POOL_SENTINEL.
    MockProtocolFeeRuleset staticCurve =
      new MockProtocolFeeRuleset({fee: _boundProtocolFee(curveFee), reverts: false});
    address nativeMathPoolSentinel = policy.NATIVE_MATH_POOL_SENTINEL();
    vm.prank(feeSetter);
    policy.setProtocolFeeRuleset(nativeMathPoolSentinel, staticCurve);

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
