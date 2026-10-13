// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IProtocolFees} from "v4-core/interfaces/IProtocolFees.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

import {V4FeeAdapter, IV4FeeAdapter} from "../src/feeAdapters/V4FeeAdapter.sol";
import {IV4FeePolicy} from "../src/interfaces/IV4FeePolicy.sol";
import {MockV4PoolManager} from "./mocks/MockV4PoolManager.sol";
import {MockFeePolicy} from "./mocks/MockFeePolicy.sol";

/// @dev Each section starts with the branch tree of one function. The tests are in the same
/// sequence as the tree. Each test sets all conditions of its branch, thus setUp has no policy or
/// pool state. The adapter only forwards to its policy, thus these tests use MockFeePolicy.
contract V4FeeAdapterTest is Test {
  using StateLibrary for IPoolManager;

  MockV4PoolManager public poolManager;
  V4FeeAdapter public adapter;
  MockERC20 public token;

  address public owner;
  address public feeSetter;
  address public tokenJar;

  function setUp() public {
    owner = makeAddr("owner");
    feeSetter = makeAddr("feeSetter");
    tokenJar = makeAddr("tokenJar");

    token = new MockERC20("Token", "TKN", 18);

    vm.startPrank(owner);
    poolManager = new MockV4PoolManager(owner);
    adapter = new V4FeeAdapter(IPoolManager(address(poolManager)), tokenJar);
    adapter.setFeeSetter(feeSetter);
    // Make the adapter the protocolFeeController of the PoolManager.
    poolManager.setProtocolFeeController(address(adapter));
    vm.stopPrank();
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
  // └── it sets the pool manager, the token jar, and the deployer as the owner

  function testFuzz_constructor(address deployer, IPoolManager manager, address jar) public {
    vm.expectEmit();
    emit Owned.OwnershipTransferred(address(0), deployer);
    vm.prank(deployer);
    V4FeeAdapter deployed = new V4FeeAdapter(manager, jar);

    assertEq(address(deployed.POOL_MANAGER()), address(manager));
    assertEq(deployed.TOKEN_JAR(), jar);
    assertEq(deployed.owner(), deployer);
    assertEq(deployed.feeSetter(), address(0));
    assertEq(address(deployed.policy()), address(0));
    assertEq(deployed.ZERO_FEE_SENTINEL(), type(uint24).max);
  }

  // ============ getFee ============
  //
  // getFee
  // ├── given the pool has an override
  // │   ├── given the override is an explicit zero
  // │   │   └── it returns zero and does not call the policy
  // │   └── given the override is not zero
  // │       └── it returns the override and does not call the policy
  // └── given the pool has no override
  //     ├── given no policy is set
  //     │   └── it returns zero
  //     └── given a policy is set
  //         └── it returns the fee from the policy

  function testFuzz_getFee_GivenTheOverrideIsAnExplicitZero(PoolKey memory key, uint24 policyFee)
    public
  {
    // Given: a policy that returns `policyFee` for all pools.
    MockFeePolicy policy = new MockFeePolicy(policyFee);
    vm.prank(owner);
    adapter.setPolicy(IV4FeePolicy(address(policy)));

    // Given: the pool has an override, and the override is an explicit zero.
    vm.prank(feeSetter);
    adapter.setPoolOverride(key.toId(), 0);

    // Then: getFee returns zero and does not call the policy.
    vm.expectCall(address(policy), abi.encodeCall(IV4FeePolicy.computeFee, (key)), 0);
    assertEq(adapter.getFee(key), 0);
  }

  function testFuzz_getFee_GivenTheOverrideIsANonzeroFee(
    PoolKey memory key,
    uint24 overrideFee,
    uint24 policyFee
  ) public {
    // Given: a policy that returns `policyFee` for all pools.
    MockFeePolicy policy = new MockFeePolicy(policyFee);
    vm.prank(owner);
    adapter.setPolicy(IV4FeePolicy(address(policy)));

    // Given: the pool has an override, and the override is not zero.
    overrideFee = _boundProtocolFee(overrideFee);
    vm.assume(overrideFee != 0);
    vm.prank(feeSetter);
    adapter.setPoolOverride(key.toId(), overrideFee);

    // Then: getFee returns the override and does not call the policy.
    vm.expectCall(address(policy), abi.encodeCall(IV4FeePolicy.computeFee, (key)), 0);
    assertEq(adapter.getFee(key), overrideFee);
  }

  function testFuzz_getFee_GivenNoPolicyIsSet(PoolKey memory key) public view {
    // Given: the pool has no override, and no policy is set.
    // Then: getFee returns zero.
    assertEq(adapter.getFee(key), 0);
  }

  function testFuzz_getFee_GivenAPolicyIsSet(PoolKey memory key, uint24 policyFee) public {
    // Given: the pool has no override.
    // Given: a policy that returns `policyFee` for all pools.
    MockFeePolicy policy = new MockFeePolicy(policyFee);
    vm.prank(owner);
    adapter.setPolicy(IV4FeePolicy(address(policy)));

    // Then: getFee returns the fee from the policy.
    vm.expectCall(address(policy), abi.encodeCall(IV4FeePolicy.computeFee, (key)));
    assertEq(adapter.getFee(key), policyFee);
  }

  // ============ triggerFeeUpdate ============
  //
  // triggerFeeUpdate
  // ├── given the pool is not initialized
  // │   └── it does not set a protocol fee and does not emit
  // └── given the pool is initialized
  //     ├── it sets the protocol fee of the pool to getFee
  //     └── it emits FeeUpdateTriggered

  function testFuzz_triggerFeeUpdate_GivenThePoolIsNotInitialized(
    address caller,
    PoolKey memory key,
    uint24 policyFee
  ) public {
    // Given: a policy that returns `policyFee` for all pools.
    MockFeePolicy policy = new MockFeePolicy(_boundProtocolFee(policyFee));
    vm.prank(owner);
    adapter.setPolicy(IV4FeePolicy(address(policy)));

    // Given: the pool is not initialized.
    // Then: triggerFeeUpdate does not set a protocol fee and does not emit.
    vm.expectCall(
      address(poolManager), abi.encodeWithSelector(IProtocolFees.setProtocolFee.selector), 0
    );
    vm.recordLogs();
    vm.prank(caller);
    adapter.triggerFeeUpdate(key);
    assertEq(vm.getRecordedLogs().length, 0);
    assertEq(poolManager.getProtocolFee(key.toId()), 0);
  }

  function testFuzz_triggerFeeUpdate_GivenThePoolIsInitialized(
    address caller,
    PoolKey memory key,
    uint24 policyFee
  ) public {
    // Given: a policy that returns `policyFee` for all pools.
    policyFee = _boundProtocolFee(policyFee);
    MockFeePolicy policy = new MockFeePolicy(policyFee);
    vm.prank(owner);
    adapter.setPolicy(IV4FeePolicy(address(policy)));

    // Given: the pool is initialized.
    poolManager.mockInitialize(key);

    // Then: triggerFeeUpdate emits FeeUpdateTriggered.
    vm.expectEmit(address(adapter));
    emit IV4FeeAdapter.FeeUpdateTriggered(caller, key.toId(), policyFee);
    vm.prank(caller);
    adapter.triggerFeeUpdate(key);

    // Then: triggerFeeUpdate sets the protocol fee of the pool to getFee.
    assertEq(poolManager.getProtocolFee(key.toId()), policyFee);
  }

  // ============ batchTriggerFeeUpdate ============
  //
  // batchTriggerFeeUpdate
  // ├── when there are no pools
  // │   └── it does not emit
  // └── when there are pools
  //     ├── it sets the protocol fee of each initialized pool to getFee
  //     ├── it does not change an uninitialized pool
  //     └── it emits FeeUpdateTriggered for each initialized pool, in sequence

  function testFuzz_batchTriggerFeeUpdate_WhenThereAreNoPools(address caller) public {
    // When: there are no pools.
    // Then: batchTriggerFeeUpdate does not emit.
    vm.recordLogs();
    vm.prank(caller);
    adapter.batchTriggerFeeUpdate(new PoolKey[](0));
    assertEq(vm.getRecordedLogs().length, 0);
  }

  function testFuzz_batchTriggerFeeUpdate_WhenThereArePools(
    address caller,
    PoolKey[8] memory candidates,
    uint256 count,
    uint8 initializedMask,
    uint24 policyFee
  ) public {
    // Given: a policy that returns `policyFee` for all pools.
    policyFee = _boundProtocolFee(policyFee);
    MockFeePolicy policy = new MockFeePolicy(policyFee);
    vm.prank(owner);
    adapter.setPolicy(IV4FeePolicy(address(policy)));

    // When: there are 1 to 8 pools. If bit i of `initializedMask` is 1, pool i is initialized.
    count = bound(count, 1, 8);
    PoolKey[] memory keys = new PoolKey[](count);
    for (uint256 i; i < count; ++i) {
      keys[i] = candidates[i];
      if ((initializedMask >> i) & 1 == 1) poolManager.mockInitialize(keys[i]);
    }
    // Read the state from the PoolManager, because `candidates` can contain the same pool two or
    // more times.
    bool[] memory initialized = new bool[](count);
    for (uint256 i; i < count; ++i) {
      (uint160 sqrtPriceX96,,,) = IPoolManager(address(poolManager)).getSlot0(keys[i].toId());
      initialized[i] = sqrtPriceX96 != 0;
    }

    // Then: batchTriggerFeeUpdate emits FeeUpdateTriggered for each initialized pool, in sequence.
    for (uint256 i; i < count; ++i) {
      if (!initialized[i]) continue;
      vm.expectEmit(address(adapter));
      emit IV4FeeAdapter.FeeUpdateTriggered(caller, keys[i].toId(), policyFee);
    }
    vm.prank(caller);
    adapter.batchTriggerFeeUpdate(keys);

    // Then: batchTriggerFeeUpdate sets the protocol fee of each initialized pool to getFee.
    // Then: batchTriggerFeeUpdate does not change an uninitialized pool.
    for (uint256 i; i < count; ++i) {
      assertEq(poolManager.getProtocolFee(keys[i].toId()), initialized[i] ? policyFee : 0);
    }
  }

  // ============ collect ============
  //
  // collect
  // ├── when there are no collect params
  // │   └── it does not emit
  // └── when there are collect params
  //     ├── when the amount is zero
  //     │   ├── it sends all accrued fees to the token jar
  //     │   └── it emits FeesCollected with the accrued amount
  //     └── when the amount is not zero
  //         ├── it sends the amount to the token jar
  //         └── it emits FeesCollected with the amount

  function testFuzz_collect_WhenThereAreNoCollectParams(address caller) public {
    // When: there are no collect params.
    // Then: collect does not emit.
    vm.recordLogs();
    vm.prank(caller);
    adapter.collect(new IV4FeeAdapter.CollectParams[](0));
    assertEq(vm.getRecordedLogs().length, 0);
  }

  function testFuzz_collect_WhenTheAmountIsZero(address caller, uint256 accrued) public {
    // Given: protocol fees accrued in the token.
    accrued = bound(accrued, 0, type(uint128).max);
    Currency currency = Currency.wrap(address(token));
    token.mint(address(poolManager), accrued);
    poolManager.setProtocolFeesAccrued(currency, accrued);

    // When: there are collect params, and the amount is zero.
    IV4FeeAdapter.CollectParams[] memory params = new IV4FeeAdapter.CollectParams[](1);
    params[0] = IV4FeeAdapter.CollectParams({currency: currency, amount: 0});

    // Then: collect emits FeesCollected with the accrued amount.
    vm.expectEmit(address(adapter));
    emit IV4FeeAdapter.FeesCollected(currency, accrued);
    vm.prank(caller);
    adapter.collect(params);

    // Then: collect sends all accrued fees to the token jar.
    assertEq(token.balanceOf(tokenJar), accrued);
    assertEq(poolManager.protocolFeesAccrued(currency), 0);
  }

  function testFuzz_collect_WhenTheAmountIsNonzero(address caller, uint256 accrued, uint256 amount)
    public
  {
    // Given: protocol fees accrued in the token.
    accrued = bound(accrued, 1, type(uint128).max);
    Currency currency = Currency.wrap(address(token));
    token.mint(address(poolManager), accrued);
    poolManager.setProtocolFeesAccrued(currency, accrued);

    // When: there are collect params, and the amount is 1 to the accrued fees.
    amount = bound(amount, 1, accrued);
    IV4FeeAdapter.CollectParams[] memory params = new IV4FeeAdapter.CollectParams[](1);
    params[0] = IV4FeeAdapter.CollectParams({currency: currency, amount: amount});

    // Then: collect emits FeesCollected with the amount.
    vm.expectEmit(address(adapter));
    emit IV4FeeAdapter.FeesCollected(currency, amount);
    vm.prank(caller);
    adapter.collect(params);

    // Then: collect sends the amount to the token jar.
    assertEq(token.balanceOf(tokenJar), amount);
    assertEq(poolManager.protocolFeesAccrued(currency), accrued - amount);
  }

  // ============ setPolicy ============
  //
  // setPolicy
  // ├── when the caller is not the owner
  // │   └── it reverts with UNAUTHORIZED
  // └── when the caller is the owner
  //     ├── it sets the policy
  //     └── it emits PolicyUpdated

  function testFuzz_setPolicy_RevertWhen_CallerIsNotTheOwner(address caller, IV4FeePolicy newPolicy)
    public
  {
    // When: the caller is not the owner.
    vm.assume(caller != owner);

    // Then: setPolicy reverts with UNAUTHORIZED.
    vm.prank(caller);
    vm.expectRevert("UNAUTHORIZED");
    adapter.setPolicy(newPolicy);
  }

  function testFuzz_setPolicy_WhenCallerIsTheOwner(
    IV4FeePolicy previousPolicy,
    IV4FeePolicy newPolicy
  ) public {
    // Given: a previous policy.
    vm.prank(owner);
    adapter.setPolicy(previousPolicy);

    // When: the caller is the owner.
    // Then: setPolicy emits PolicyUpdated.
    vm.expectEmit(address(adapter));
    emit IV4FeeAdapter.PolicyUpdated(address(previousPolicy), address(newPolicy));
    vm.prank(owner);
    adapter.setPolicy(newPolicy);

    // Then: setPolicy sets the policy.
    assertEq(address(adapter.policy()), address(newPolicy));
  }

  // ============ setFeeSetter ============
  //
  // setFeeSetter
  // ├── when the caller is not the owner
  // │   └── it reverts with UNAUTHORIZED
  // └── when the caller is the owner
  //     ├── when the new fee setter is the zero address
  //     │   └── it reverts with ZeroAddress
  //     └── when the new fee setter is not the zero address
  //         ├── it sets the fee setter
  //         └── it emits FeeSetterUpdated

  function testFuzz_setFeeSetter_RevertWhen_CallerIsNotTheOwner(
    address caller,
    address newFeeSetter
  ) public {
    // When: the caller is not the owner.
    vm.assume(caller != owner);

    // Then: setFeeSetter reverts with UNAUTHORIZED.
    vm.prank(caller);
    vm.expectRevert("UNAUTHORIZED");
    adapter.setFeeSetter(newFeeSetter);
  }

  function test_setFeeSetter_RevertWhen_TheNewFeeSetterIsTheZeroAddress() public {
    // When: the caller is the owner, and the new fee setter is the zero address.
    // Then: setFeeSetter reverts with ZeroAddress.
    vm.prank(owner);
    vm.expectRevert(IV4FeeAdapter.ZeroAddress.selector);
    adapter.setFeeSetter(address(0));
  }

  function testFuzz_setFeeSetter_WhenTheNewFeeSetterIsNotTheZeroAddress(address newFeeSetter)
    public
  {
    // When: the caller is the owner, and the new fee setter is not the zero address.
    vm.assume(newFeeSetter != address(0));

    // Then: setFeeSetter emits FeeSetterUpdated.
    vm.expectEmit(address(adapter));
    emit IV4FeeAdapter.FeeSetterUpdated(feeSetter, newFeeSetter);
    vm.prank(owner);
    adapter.setFeeSetter(newFeeSetter);

    // Then: setFeeSetter sets the fee setter.
    assertEq(adapter.feeSetter(), newFeeSetter);
  }

  // ============ setPoolOverride ============
  //
  // setPoolOverride
  // ├── when the caller is not the fee setter
  // │   └── it reverts with Unauthorized
  // └── when the caller is the fee setter
  //     ├── when the fee is zero
  //     │   ├── it sets the override to ZERO_FEE_SENTINEL
  //     │   └── it emits PoolOverrideUpdated with ZERO_FEE_SENTINEL
  //     └── when the fee is not zero
  //         ├── when the fee is above MAX_PROTOCOL_FEE
  //         │   └── it reverts with InvalidFeeValue
  //         └── when the fee is at or below MAX_PROTOCOL_FEE
  //             ├── it sets the override to the fee
  //             └── it emits PoolOverrideUpdated with the fee

  function testFuzz_setPoolOverride_RevertWhen_CallerIsNotTheFeeSetter(
    address caller,
    PoolId poolId,
    uint24 fee
  ) public {
    // When: the caller is not the fee setter.
    vm.assume(caller != feeSetter);

    // Then: setPoolOverride reverts with Unauthorized.
    vm.prank(caller);
    vm.expectRevert(IV4FeeAdapter.Unauthorized.selector);
    adapter.setPoolOverride(poolId, fee);
  }

  function testFuzz_setPoolOverride_WhenTheFeeIsZero(PoolId poolId) public {
    // When: the caller is the fee setter, and the fee is zero.
    // Then: setPoolOverride emits PoolOverrideUpdated with ZERO_FEE_SENTINEL.
    vm.expectEmit(address(adapter));
    emit IV4FeeAdapter.PoolOverrideUpdated(poolId, type(uint24).max);
    vm.prank(feeSetter);
    adapter.setPoolOverride(poolId, 0);

    // Then: setPoolOverride sets the override to ZERO_FEE_SENTINEL.
    assertEq(adapter.poolOverrides(poolId), type(uint24).max);
  }

  function testFuzz_setPoolOverride_RevertWhen_TheFeeIsInvalid(PoolId poolId, uint24 fee) public {
    // When: the caller is the fee setter, and the fee is not zero.
    // When: the fee is above MAX_PROTOCOL_FEE in one or two directions.
    vm.assume(!ProtocolFeeLibrary.isValidProtocolFee(fee));

    // Then: setPoolOverride reverts with InvalidFeeValue.
    vm.prank(feeSetter);
    vm.expectRevert(IV4FeeAdapter.InvalidFeeValue.selector);
    adapter.setPoolOverride(poolId, fee);
  }

  function testFuzz_setPoolOverride_WhenTheFeeIsValid(PoolId poolId, uint24 fee) public {
    // When: the caller is the fee setter, and the fee is not zero.
    // When: the fee is at or below MAX_PROTOCOL_FEE.
    fee = _boundProtocolFee(fee);
    vm.assume(fee != 0);

    // Then: setPoolOverride emits PoolOverrideUpdated with the fee.
    vm.expectEmit(address(adapter));
    emit IV4FeeAdapter.PoolOverrideUpdated(poolId, fee);
    vm.prank(feeSetter);
    adapter.setPoolOverride(poolId, fee);

    // Then: setPoolOverride sets the override to the fee.
    assertEq(adapter.poolOverrides(poolId), fee);
  }

  // ============ clearPoolOverride ============
  //
  // clearPoolOverride
  // ├── when the caller is not the fee setter
  // │   └── it reverts with Unauthorized
  // └── when the caller is the fee setter
  //     ├── it removes the override
  //     └── it emits PoolOverrideUpdated with zero

  function testFuzz_clearPoolOverride_RevertWhen_CallerIsNotTheFeeSetter(
    address caller,
    PoolId poolId
  ) public {
    // When: the caller is not the fee setter.
    vm.assume(caller != feeSetter);

    // Then: clearPoolOverride reverts with Unauthorized.
    vm.prank(caller);
    vm.expectRevert(IV4FeeAdapter.Unauthorized.selector);
    adapter.clearPoolOverride(poolId);
  }

  function testFuzz_clearPoolOverride_WhenCallerIsTheFeeSetter(PoolId poolId, uint24 overrideFee)
    public
  {
    // Given: the pool has an override.
    vm.prank(feeSetter);
    adapter.setPoolOverride(poolId, _boundProtocolFee(overrideFee));

    // When: the caller is the fee setter.
    // Then: clearPoolOverride emits PoolOverrideUpdated with zero.
    vm.expectEmit(address(adapter));
    emit IV4FeeAdapter.PoolOverrideUpdated(poolId, 0);
    vm.prank(feeSetter);
    adapter.clearPoolOverride(poolId);

    // Then: clearPoolOverride removes the override.
    assertEq(adapter.poolOverrides(poolId), 0);
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
    adapter.transferOwnership(newOwner);
  }

  function testFuzz_transferOwnership_WhenCallerIsTheOwner(address newOwner) public {
    // When: the caller is the owner.
    // Then: transferOwnership emits OwnershipTransferred.
    vm.expectEmit(address(adapter));
    emit Owned.OwnershipTransferred(owner, newOwner);
    vm.prank(owner);
    adapter.transferOwnership(newOwner);

    // Then: transferOwnership sets the owner.
    assertEq(adapter.owner(), newOwner);
  }
}
