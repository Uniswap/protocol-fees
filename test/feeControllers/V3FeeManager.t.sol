// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {V3FeeManager} from "../../src/feeControllers/V3FeeManager.sol";
import {IUniswapV3PoolOwnerActions} from "../../src/interfaces/IUniswapV3PoolOwnerActions.sol";
import {IUniswapV3FactoryOwnerActions} from "../../src/interfaces/IUniswapV3FactoryOwnerActions.sol";
import {V3FeeManagerHarness} from "./harnesses/V3FeeManagerHarness.sol";
import {MockUniswapV3Pool} from "./mocks/MockUniswapV3Pool.sol";
import {MockUniswapV3Factory} from "./mocks/MockUniswapV3Factory.sol";

contract V3FeeManagerTest is Test {
  V3FeeManagerHarness feeManager;
  address admin = makeAddr("Admin");
  address payoutReceiver;
  MockUniswapV3Pool pool;
  MockUniswapV3Pool pool2;
  MockUniswapV3Pool pool3;
  MockUniswapV3Factory factory;

  function setUp() public {
    vm.label(admin, "Admin");

    payoutReceiver = makeAddr("Payout Receiver");

    pool = new MockUniswapV3Pool();
    vm.label(address(pool), "Pool 1");
    pool2 = new MockUniswapV3Pool();
    vm.label(address(pool2), "Pool 2");
    pool3 = new MockUniswapV3Pool();
    vm.label(address(pool3), "Pool 3");

    factory = new MockUniswapV3Factory();
    vm.label(address(factory), "Factory");
  }

  function _deployFeeManager(uint256 _feeSeed) public {
    uint8 _fee = _getValidProtocolFee(_feeSeed);

    feeManager = new V3FeeManagerHarness(admin, factory, _fee, payoutReceiver);
    vm.label(address(feeManager), "Factory Owner");
  }

  function _deployFeeManager() public {
    _deployFeeManager(10);
  }

  function _createPools(uint256 _numPools)
    internal
    returns (IUniswapV3PoolOwnerActions[] memory _pools)
  {
    _pools = new IUniswapV3PoolOwnerActions[](_numPools);
    for (uint256 i = 0; i < _numPools; i++) {
      _pools[i] = IUniswapV3PoolOwnerActions(address(new MockUniswapV3Pool()));
      vm.label(address(_pools[i]), string.concat("Created pool ", string(abi.encodePacked(i))));
    }
    return _pools;
  }

  function _getValidProtocolFee() internal returns (uint8 _fee) {
    _fee = _getValidProtocolFee(uint8(vm.randomUint(0, 10)));
  }

  function _getValidProtocolFee(uint256 _seed) internal pure returns (uint8 _fee) {
    _fee = uint8(bound(_seed, 0, 10));
    if (_fee == 0) return _fee;
    if (_fee < 4) _fee += 3;
  }

  function _generateValidFeeProtocolOverrides(IUniswapV3PoolOwnerActions[] memory _pools)
    internal
    returns (V3FeeManager.FeeProtocolOverride[] memory)
  {
    V3FeeManager.FeeProtocolOverride[] memory _override =
      new V3FeeManager.FeeProtocolOverride[](_pools.length);
    for (uint256 i = 0; i < _override.length; i++) {
      _override[i] = V3FeeManager.FeeProtocolOverride({
        pool: _pools[i],
        feeProtocol0: _getValidProtocolFee(),
        feeProtocol1: _getValidProtocolFee()
      });
    }
    return _override;
  }
}

contract Constructor is V3FeeManagerTest {
  function testFuzz_SetsAllParametersToArbitraryValues(
    address _admin,
    address _factory,
    uint256 _feeSeed,
    address _payoutReceiver
  ) public {
    vm.assume(_admin != address(0));
    uint8 _fee = _getValidProtocolFee(_feeSeed);
    V3FeeManagerHarness _feeManager = new V3FeeManagerHarness(
      _admin, IUniswapV3FactoryOwnerActions(_factory), _fee, address(_payoutReceiver)
    );
    assertEq(_feeManager.admin(), _admin);
    assertEq(address(_feeManager.FACTORY()), address(_factory));
    assertEq(address(_feeManager.FEE_RECEIVER()), _payoutReceiver);
    assertEq(_feeManager.globalProtocolFee(), _fee);
  }

  function testFuzz_EmitsAdminSetEvent(
    address _admin,
    address _factory,
    uint256 _feeSeed,
    address _payoutReceiver
  ) public {
    vm.assume(_admin != address(0));
    uint8 _fee = _getValidProtocolFee(_feeSeed);

    vm.expectEmit();
    emit V3FeeManager.AdminSet(address(0), _admin);
    new V3FeeManagerHarness(
      _admin, IUniswapV3FactoryOwnerActions(_factory), _fee, address(_payoutReceiver)
    );
  }

  function testFuzz_RevertIf_TheAdminIsAddressZero(
    address _factory,
    uint256 _feeSeed,
    address _payoutReceiver
  ) public {
    uint8 _fee = _getValidProtocolFee(_feeSeed);

    vm.expectRevert(V3FeeManager.V3FeeManager__InvalidAddress.selector);
    new V3FeeManagerHarness(
      address(0), IUniswapV3FactoryOwnerActions(_factory), _fee, address(_payoutReceiver)
    );
  }

  function testFuzz_RevertIf_FeeIsNotInTheValidRange(
    address _admin,
    address _factory,
    uint8 _fee,
    address _payoutReceiver
  ) public {
    vm.assume(_fee != 0 && (_fee < 4 || _fee > 10));
    vm.assume(_admin != address(0));

    vm.expectRevert(V3FeeManager.V3FeeManager__InvalidGlobalProtocolFee.selector);
    new V3FeeManagerHarness(
      _admin, IUniswapV3FactoryOwnerActions(_factory), _fee, address(_payoutReceiver)
    );
  }
}

contract _SetAdmin is V3FeeManagerTest {
  function testFuzz_UpdatesTheAdmin(address _newAdmin) public {
    vm.assume(_newAdmin != address(0));
    _deployFeeManager();

    feeManager.exposed_setAdmin(_newAdmin);

    assertEq(feeManager.admin(), _newAdmin);
  }

  function testFuzz_EmitsAnEventWhenUpdatingTheAdmin(address _newAdmin) public {
    vm.assume(_newAdmin != address(0));
    _deployFeeManager();

    vm.expectEmit();
    emit V3FeeManager.AdminSet(admin, _newAdmin);
    feeManager.exposed_setAdmin(_newAdmin);
  }

  function test_RevertIf_TheNewAdminIsAddressZero() public {
    _deployFeeManager();

    vm.expectRevert(V3FeeManager.V3FeeManager__InvalidAddress.selector);
    feeManager.exposed_setAdmin(address(0));
  }
}

contract SetAdmin is V3FeeManagerTest {
  function testFuzz_UpdatesTheAdminWhenCalledByTheCurrentAdmin(address _newAdmin) public {
    vm.assume(_newAdmin != address(0));
    _deployFeeManager();

    vm.prank(admin);
    feeManager.setAdmin(_newAdmin);

    assertEq(feeManager.admin(), _newAdmin);
  }

  function testFuzz_EmitsAnEventWhenUpdatingTheAdmin(address _newAdmin) public {
    vm.assume(_newAdmin != address(0));
    _deployFeeManager();

    vm.expectEmit();
    vm.prank(admin);
    emit V3FeeManager.AdminSet(admin, _newAdmin);
    feeManager.setAdmin(_newAdmin);
  }

  function testFuzz_RevertIf_TheCallerIsNotTheCurrentAdmin(address _notAdmin, address _newAdmin)
    public
  {
    _deployFeeManager();

    vm.assume(_notAdmin != admin);

    vm.expectRevert(V3FeeManager.V3FeeManager__Unauthorized.selector);
    vm.prank(_notAdmin);
    feeManager.setAdmin(_newAdmin);
  }

  function test_RevertIf_TheNewAdminIsAddressZero() public {
    _deployFeeManager();

    vm.expectRevert(V3FeeManager.V3FeeManager__InvalidAddress.selector);
    vm.prank(admin);
    feeManager.setAdmin(address(0));
  }
}

contract _SetGlobalProtocolFee is V3FeeManagerTest {
  function testFuzz_SetsTheGlobalProtocolFee(uint256 _initFeeSeed, uint256 _updatedFeeSeed) public {
    _deployFeeManager(_initFeeSeed);

    uint8 _updatedFee = _getValidProtocolFee(_updatedFeeSeed);
    feeManager.exposed_setGlobalProtocolFee(_updatedFee);
    assertEq(feeManager.globalProtocolFee(), _updatedFee);
  }

  function testFuzz_EmitsGlobalProtocolFeeSetEvent(uint256 _initFeeSeed, uint256 _updatedFeeSeed)
    public
  {
    _deployFeeManager(_initFeeSeed);

    uint8 _updatedFee = _getValidProtocolFee(_updatedFeeSeed);
    vm.expectEmit();
    emit V3FeeManager.GlobalProtocolFeeSet(feeManager.globalProtocolFee(), _updatedFee);
    feeManager.exposed_setGlobalProtocolFee(_updatedFee);
  }

  function testFuzz_RevertIf_FeeIsLow(uint256 _initFeeSeed, uint256 _updatedFeeSeed) public {
    _deployFeeManager(_initFeeSeed);

    uint8 _updatedFee = uint8(bound(_updatedFeeSeed, 1, 3));
    vm.expectRevert(V3FeeManager.V3FeeManager__InvalidGlobalProtocolFee.selector);
    feeManager.exposed_setGlobalProtocolFee(_updatedFee);
  }

  function testFuzz_RevertIf_FeeIsHigh(uint256 _initFeeSeed, uint256 _updatedFeeSeed) public {
    _deployFeeManager(_initFeeSeed);

    uint8 _updatedFee = uint8(bound(_updatedFeeSeed, 11, type(uint8).max));
    vm.expectRevert(V3FeeManager.V3FeeManager__InvalidGlobalProtocolFee.selector);
    feeManager.exposed_setGlobalProtocolFee(_updatedFee);
  }
}

contract SetGlobalProtocolFee is V3FeeManagerTest {
  function testFuzz_SetsTheGlobalProtocolFee(uint256 _initFeeSeed, uint256 _updatedFeeSeed) public {
    _deployFeeManager(_initFeeSeed);

    uint8 _updatedFee = _getValidProtocolFee(_updatedFeeSeed);

    vm.prank(admin);
    feeManager.setGlobalProtocolFee(_updatedFee);
    assertEq(feeManager.globalProtocolFee(), _updatedFee);
  }

  function testFuzz_EmitsGlobalProtocolFeeSetEvent(uint256 _initFeeSeed, uint256 _updatedFeeSeed)
    public
  {
    _deployFeeManager(_initFeeSeed);

    uint8 _updatedFee = _getValidProtocolFee(_updatedFeeSeed);

    vm.expectEmit();
    emit V3FeeManager.GlobalProtocolFeeSet(feeManager.globalProtocolFee(), _updatedFee);
    vm.prank(admin);
    feeManager.setGlobalProtocolFee(_updatedFee);
  }

  function testFuzz_RevertIf_FeeIsLow(uint256 _initFeeSeed, uint256 _updatedFeeSeed) public {
    _deployFeeManager(_initFeeSeed);

    uint8 _updatedFee = uint8(bound(_updatedFeeSeed, 1, 3));
    vm.expectRevert(V3FeeManager.V3FeeManager__InvalidGlobalProtocolFee.selector);
    vm.prank(admin);
    feeManager.setGlobalProtocolFee(_updatedFee);
  }

  function testFuzz_RevertIf_FeeIsHigh(uint256 _initFeeSeed, uint256 _updatedFeeSeed) public {
    _deployFeeManager(_initFeeSeed);

    uint8 _updatedFee = uint8(bound(_updatedFeeSeed, 11, type(uint8).max));
    vm.expectRevert(V3FeeManager.V3FeeManager__InvalidGlobalProtocolFee.selector);
    vm.prank(admin);
    feeManager.setGlobalProtocolFee(_updatedFee);
  }

  function testFuzz_RevertIf_CalledByNonAdmin(
    address _nonAdmin,
    uint256 _initFeeSeed,
    uint256 _updatedFeeSeed
  ) public {
    vm.assume(_nonAdmin != admin);
    _deployFeeManager(_initFeeSeed);

    uint8 _updatedFee = _getValidProtocolFee(_updatedFeeSeed);

    vm.expectRevert(V3FeeManager.V3FeeManager__Unauthorized.selector);
    vm.prank(_nonAdmin);
    feeManager.setGlobalProtocolFee(_updatedFee);
  }
}

contract EnableFeeAmount is V3FeeManagerTest {
  function testFuzz_ForwardsParametersToTheEnableFeeAmountMethodOnTheFactory(
    uint24 _fee,
    int24 _tickSpacing
  ) public {
    _deployFeeManager();

    vm.prank(admin);
    feeManager.enableFeeAmount(_fee, _tickSpacing);

    assertEq(factory.lastParam__enableFeeAmount_fee(), _fee);
    assertEq(factory.lastParam__enableFeeAmount_tickSpacing(), _tickSpacing);
  }

  function testFuzz_RevertIf_TheCallerIsNotTheAdmin(
    address _notAdmin,
    uint24 _fee,
    int24 _tickSpacing
  ) public {
    _deployFeeManager();
    vm.assume(_notAdmin != admin);

    vm.expectRevert(V3FeeManager.V3FeeManager__Unauthorized.selector);
    vm.prank(_notAdmin);
    feeManager.enableFeeAmount(_fee, _tickSpacing);
  }
}

contract SetFeeProtocol is V3FeeManagerTest {
  function testFuzz_SetsPoolFeeProtocolsToGlobalFeeProtocol(uint256 _globalFeeSeed) public {
    uint8 _fee = _getValidProtocolFee(_globalFeeSeed);
    _deployFeeManager(_fee);

    vm.prank(admin);
    feeManager.setFeeProtocol(pool);

    assertEq(pool.lastParam__setFeeProtocol_feeProtocol0(), _fee);
    assertEq(pool.lastParam__setFeeProtocol_feeProtocol1(), _fee);
  }

  function testFuzz_CanBeCalledByNonAdmin(address _notAdmin, uint256 _globalFeeSeed) public {
    uint8 _fee = _getValidProtocolFee(_globalFeeSeed);
    _deployFeeManager(_fee);
    vm.assume(_notAdmin != admin);

    vm.prank(_notAdmin);
    feeManager.setFeeProtocol(pool);

    assertEq(pool.lastParam__setFeeProtocol_feeProtocol0(), _fee);
    assertEq(pool.lastParam__setFeeProtocol_feeProtocol1(), _fee);
  }

  function testFuzz_SetsMultiplePoolsFeeProtocolsToGlobalFeeProtocol(uint256 _globalFeeSeed) public {
    uint8 _fee = _getValidProtocolFee(_globalFeeSeed);
    _deployFeeManager(_fee);

    IUniswapV3PoolOwnerActions[] memory _pools = new IUniswapV3PoolOwnerActions[](3);
    _pools[0] = IUniswapV3PoolOwnerActions(address(pool));
    _pools[1] = IUniswapV3PoolOwnerActions(address(pool2));
    _pools[2] = IUniswapV3PoolOwnerActions(address(pool3));

    // Protocol fees have not been set.
    assertEq(pool.lastParam__setFeeProtocol_feeProtocol0(), 0);
    assertEq(pool.lastParam__setFeeProtocol_feeProtocol1(), 0);
    assertEq(pool2.lastParam__setFeeProtocol_feeProtocol0(), 0);
    assertEq(pool2.lastParam__setFeeProtocol_feeProtocol1(), 0);
    assertEq(pool3.lastParam__setFeeProtocol_feeProtocol0(), 0);
    assertEq(pool3.lastParam__setFeeProtocol_feeProtocol1(), 0);

    feeManager.setFeeProtocol(_pools);

    assertEq(pool.lastParam__setFeeProtocol_feeProtocol0(), _fee);
    assertEq(pool.lastParam__setFeeProtocol_feeProtocol1(), _fee);
    assertEq(pool2.lastParam__setFeeProtocol_feeProtocol0(), _fee);
    assertEq(pool2.lastParam__setFeeProtocol_feeProtocol1(), _fee);
    assertEq(pool3.lastParam__setFeeProtocol_feeProtocol0(), _fee);
    assertEq(pool3.lastParam__setFeeProtocol_feeProtocol1(), _fee);
  }

  function testFuzz_SetsOverrideAfterOverrideUnset(
    uint8 _feeProtocol0Initial,
    uint8 _feeProtocol1Initial,
    uint8 _feeProtocol0Final,
    uint8 _feeProtocol1Final
  ) public {
    _deployFeeManager();
    IUniswapV3PoolOwnerActions[] memory _pools = new IUniswapV3PoolOwnerActions[](1);
    _pools[0] = IUniswapV3PoolOwnerActions(address(pool));
    V3FeeManager.FeeProtocolOverride[] memory overrides = new V3FeeManager.FeeProtocolOverride[](1);
    overrides[0] = V3FeeManager.FeeProtocolOverride({
      pool: pool,
      feeProtocol0: _feeProtocol0Initial,
      feeProtocol1: _feeProtocol1Initial
    });

    vm.prank(admin);
    feeManager.enactFeeProtocolOverride(overrides);

    vm.prank(admin);
    feeManager.removeFeeProtocolOverride(_pools);

    overrides[0] = V3FeeManager.FeeProtocolOverride({
      pool: pool,
      feeProtocol0: _feeProtocol0Final,
      feeProtocol1: _feeProtocol1Final
    });
    vm.prank(admin);
    feeManager.enactFeeProtocolOverride(overrides);

    assertEq(feeManager.isFeeProtocolOverridden(pool), true);
    assertEq(pool.lastParam__setFeeProtocol_feeProtocol0(), _feeProtocol0Final);
    assertEq(pool.lastParam__setFeeProtocol_feeProtocol1(), _feeProtocol1Final);
  }

  function testFuzz_RevertIf_FeeProtocolOverrideIsTrueWhenPassingMultiplePools(
    address _actor,
    uint256 _numPools,
    uint256 _randomSeed
  ) public {
    _deployFeeManager();
    _numPools = bound(_numPools, 1, 300);
    uint256 _randomPoolIndex = bound(_randomSeed, 0, _numPools - 1);
    IUniswapV3PoolOwnerActions[] memory _pools = _createPools(_numPools);
    V3FeeManager.FeeProtocolOverride[] memory overrides = _generateValidFeeProtocolOverrides(_pools);

    vm.prank(admin);
    feeManager.enactFeeProtocolOverride(overrides);

    vm.expectRevert(
      abi.encodeWithSelector(
        V3FeeManager.V3FeeManager__FeeProtocolOverride.selector, _pools[_randomPoolIndex]
      )
    );
    vm.prank(_actor);
    feeManager.setFeeProtocol(_pools[_randomPoolIndex]);
  }

  function testFuzz_RevertIf_FeeProtocolOverrideIsTrue(address _actor, uint256 _numPools) public {
    _deployFeeManager();
    _numPools = bound(_numPools, 1, 300);
    IUniswapV3PoolOwnerActions[] memory _pools = _createPools(_numPools);
    V3FeeManager.FeeProtocolOverride[] memory overrides = _generateValidFeeProtocolOverrides(_pools);

    vm.prank(admin);
    feeManager.enactFeeProtocolOverride(overrides);

    vm.expectRevert(
      abi.encodeWithSelector(V3FeeManager.V3FeeManager__FeeProtocolOverride.selector, _pools[0])
    );
    vm.prank(_actor);
    feeManager.setFeeProtocol(_pools);
  }
}

contract EnactFeeProtocolOverride is V3FeeManagerTest {
  function testFuzz_SetsIsFeeProtocolOverride(uint8 _feeProtocol0, uint8 _feeProtocol1) public {
    _deployFeeManager();
    IUniswapV3PoolOwnerActions[] memory _pools = new IUniswapV3PoolOwnerActions[](1);
    _pools[0] = IUniswapV3PoolOwnerActions(address(pool));
    V3FeeManager.FeeProtocolOverride[] memory overrides = new V3FeeManager.FeeProtocolOverride[](1);
    overrides[0] = V3FeeManager.FeeProtocolOverride({
      pool: pool,
      feeProtocol0: _feeProtocol0,
      feeProtocol1: _feeProtocol1
    });

    vm.prank(admin);
    feeManager.enactFeeProtocolOverride(overrides);

    assertEq(feeManager.isFeeProtocolOverridden(pool), true);
  }

  function testFuzz_SetsFeeProtocolOverride(uint256 _numPools) public {
    _numPools = bound(_numPools, 1, 300);
    _deployFeeManager();
    IUniswapV3PoolOwnerActions[] memory _pools = _createPools(_numPools);
    V3FeeManager.FeeProtocolOverride[] memory overrides = _generateValidFeeProtocolOverrides(_pools);

    vm.prank(admin);
    feeManager.enactFeeProtocolOverride(overrides);

    for (uint256 i = 0; i < overrides.length; i++) {
      assertEq(
        MockUniswapV3Pool(address(overrides[i].pool)).lastParam__setFeeProtocol_feeProtocol0(),
        overrides[i].feeProtocol0
      );
      assertEq(
        MockUniswapV3Pool(address(overrides[i].pool)).lastParam__setFeeProtocol_feeProtocol1(),
        overrides[i].feeProtocol1
      );
      assertEq(feeManager.isFeeProtocolOverridden(overrides[i].pool), true);
    }
  }

  function testFuzz_EmitsFeeProtocolOverrideEnactedEvent(uint256 _numPools) public {
    _numPools = bound(_numPools, 1, 300);
    _deployFeeManager();
    IUniswapV3PoolOwnerActions[] memory _pools = _createPools(_numPools);
    V3FeeManager.FeeProtocolOverride[] memory overrides = _generateValidFeeProtocolOverrides(_pools);

    vm.expectEmit();
    for (uint256 i = 0; i < overrides.length; i++) {
      emit V3FeeManager.FeeProtocolOverrideEnacted(
        overrides[i].pool, overrides[i].feeProtocol0, overrides[i].feeProtocol1
      );
    }
    vm.prank(admin);
    feeManager.enactFeeProtocolOverride(overrides);
  }

  function testFuzz_RevertIf_CalledByNonAdmin(
    address _nonAdmin,
    V3FeeManager.FeeProtocolOverride[] memory _overrides
  ) public {
    vm.assume(_nonAdmin != admin);
    _deployFeeManager();

    vm.expectRevert(V3FeeManager.V3FeeManager__Unauthorized.selector);
    vm.prank(_nonAdmin);
    feeManager.enactFeeProtocolOverride(_overrides);
  }
}

contract RemoveFeeProtocolOverride is V3FeeManagerTest {
  function testFuzz_RemovesFeeProtocolOverride(uint256 _numPools) public {
    _deployFeeManager();
    _numPools = bound(_numPools, 1, 300);
    IUniswapV3PoolOwnerActions[] memory _pools = _createPools(_numPools);
    V3FeeManager.FeeProtocolOverride[] memory _overrides =
      _generateValidFeeProtocolOverrides(_pools);

    // set up: set fee protocol override on each pool in _pools
    vm.prank(admin);
    feeManager.enactFeeProtocolOverride(_overrides);

    // now remove the fee protocol override
    vm.prank(admin);
    feeManager.removeFeeProtocolOverride(_pools);

    for (uint256 i = 0; i < _pools.length; i++) {
      assertEq(feeManager.isFeeProtocolOverridden(_pools[i]), false);
    }
  }

  function testFuzz_SetsGlobalFeeProtocolAfterRemovingOverride(uint256 _numPools) public {
    _deployFeeManager();
    _numPools = bound(_numPools, 1, 300);
    IUniswapV3PoolOwnerActions[] memory _pools = _createPools(_numPools);
    V3FeeManager.FeeProtocolOverride[] memory _overrides =
      _generateValidFeeProtocolOverrides(_pools);

    // set up: set fee protocol override on each pool in _pools
    vm.prank(admin);
    feeManager.enactFeeProtocolOverride(_overrides);

    // now remove the fee protocol override
    vm.prank(admin);
    feeManager.removeFeeProtocolOverride(_pools);

    for (uint256 i = 0; i < _pools.length; i++) {
      assertEq(
        MockUniswapV3Pool(address(_pools[i])).lastParam__setFeeProtocol_feeProtocol0(),
        feeManager.globalProtocolFee()
      );
      assertEq(
        MockUniswapV3Pool(address(_pools[i])).lastParam__setFeeProtocol_feeProtocol1(),
        feeManager.globalProtocolFee()
      );
    }
  }

  function testFuzz_EmitsFeeProtocolOverrideRemovedEvent(uint256 _numPools) public {
    _numPools = bound(_numPools, 1, 300);
    _deployFeeManager();
    IUniswapV3PoolOwnerActions[] memory _pools = _createPools(_numPools);
    V3FeeManager.FeeProtocolOverride[] memory _overrides =
      _generateValidFeeProtocolOverrides(_pools);

    // set up: set fee protocol override on each pool in _pools
    vm.prank(admin);
    feeManager.enactFeeProtocolOverride(_overrides);

    vm.expectEmit();
    for (uint256 i = 0; i < _pools.length; i++) {
      emit V3FeeManager.FeeProtocolOverrideRemoved(_pools[i]);
    }
    vm.prank(admin);
    feeManager.removeFeeProtocolOverride(_pools);
  }

  function testFuzz_RevertIf_CalledByNonAdmin(
    address _nonAdmin,
    IUniswapV3PoolOwnerActions[] memory _pools
  ) public {
    vm.assume(_nonAdmin != admin);
    _deployFeeManager();

    vm.expectRevert(V3FeeManager.V3FeeManager__Unauthorized.selector);
    vm.prank(_nonAdmin);
    feeManager.removeFeeProtocolOverride(_pools);
  }
}

contract ClaimFees is V3FeeManagerTest {
  function _buildClaimInputs(uint128 _amount0Requested, uint128 _amount1Requested)
    internal
    view
    returns (V3FeeManager.ClaimInputData[] memory _inputs)
  {
    V3FeeManager.ClaimInputData memory _input = V3FeeManager.ClaimInputData({
      pool: pool,
      amount0Requested: _amount0Requested,
      amount1Requested: _amount1Requested
    });
    _inputs = new V3FeeManager.ClaimInputData[](1);
    _inputs[0] = _input;
  }

  function testFuzz_CallsPoolCollectProtocolMethodWithRecipientAndAmountsRequestedAndReturnsForwardedFeeAmountsFromPool(
    address _caller,
    uint128 _amount0,
    uint128 _amount1
  ) public {
    _deployFeeManager();

    vm.assume(_caller != address(0));

    V3FeeManager.ClaimInputData[] memory _inputDataArray = _buildClaimInputs(_amount0, _amount1);

    vm.startPrank(_caller);
    V3FeeManager.ClaimOutputData[] memory _claimOutputs = feeManager.claimFees(_inputDataArray);
    vm.stopPrank();

    V3FeeManager.ClaimOutputData memory _claimOutput = _claimOutputs[0];

    assertEq(pool.lastParam__collectProtocol_recipient(), feeManager.FEE_RECEIVER());
    assertEq(pool.lastParam__collectProtocol_amount0Requested(), _amount0);
    assertEq(pool.lastParam__collectProtocol_amount1Requested(), _amount1);
    assertEq(_claimOutput.amount0, _amount0);
    assertEq(_claimOutput.amount1, _amount1);
  }

  function testFuzz_EmitsAnEventWithFeeClaimParameters(
    address _caller,
    uint128 _amount0,
    uint128 _amount1
  ) public {
    _deployFeeManager();

    vm.assume(_caller != address(0));

    V3FeeManager.ClaimInputData[] memory _inputDataArray = _buildClaimInputs(_amount0, _amount1);

    vm.startPrank(_caller);
    vm.expectEmit();
    emit V3FeeManager.FeesClaimed(
      address(pool), _caller, feeManager.FEE_RECEIVER(), _amount0, _amount1
    );
    feeManager.claimFees(_inputDataArray);
    vm.stopPrank();
  }

  function testFuzz_RevertIf_CallerExpectsMoreFeesThanPoolPaysOut(
    address _caller,
    uint128 _amount0Requested,
    uint128 _amount1Requested,
    uint128 _amount0Collected,
    uint128 _amount1Collected
  ) public {
    _deployFeeManager();
    vm.assume(_caller != address(0));
    _amount0Requested = uint128(bound(_amount0Requested, 1, type(uint128).max));
    _amount1Requested = uint128(bound(_amount1Requested, 1, type(uint128).max));

    // sometimes get less amount0, other times get less amount1
    // uses arbitrary randomness via fuzzed _amount0Collected
    if (_amount0Collected % 2 == 0) {
      _amount0Collected = uint128(bound(_amount0Collected, 0, _amount0Requested - 1));
    } else {
      _amount1Collected = uint128(bound(_amount1Collected, 0, _amount1Requested - 1));
    }
    pool.setNextReturn__collectProtocol(_amount0Collected, _amount1Collected);

    vm.startPrank(_caller);
    V3FeeManager.ClaimInputData[] memory _inputDataArray =
      _buildClaimInputs(_amount0Requested, _amount1Requested);

    vm.expectRevert(V3FeeManager.V3FeeManager__InsufficientFeesCollected.selector);
    feeManager.claimFees(_inputDataArray);
    vm.stopPrank();
  }

  function test_RevertIf_NoClaimInputsProvided() public {
    _deployFeeManager();

    vm.expectRevert(V3FeeManager.V3FeeManager__NoClaimInputProvided.selector);
    feeManager.claimFees(new V3FeeManager.ClaimInputData[](0));
  }

  function testFuzz_TransfersPayoutForCollectingFeesFromMultiplePools(
    address _caller,
    uint128 _amount0,
    uint128 _amount1,
    uint128 _amount2,
    uint128 _amount3
  ) public {
    _deployFeeManager();

    _amount0 = uint128(bound(_amount0, 1, type(uint128).max));
    _amount1 = uint128(bound(_amount1, 1, type(uint128).max));
    _amount2 = uint128(bound(_amount2, 1, type(uint128).max));
    _amount3 = uint128(bound(_amount3, 1, type(uint128).max));

    V3FeeManager.ClaimInputData memory _inputA = V3FeeManager.ClaimInputData({
      pool: pool,
      amount0Requested: _amount0,
      amount1Requested: _amount1
    });
    V3FeeManager.ClaimInputData memory _inputB = V3FeeManager.ClaimInputData({
      pool: pool2,
      amount0Requested: _amount2,
      amount1Requested: _amount3
    });
    V3FeeManager.ClaimInputData[] memory _inputs = new V3FeeManager.ClaimInputData[](2);
    _inputs[0] = _inputA;
    _inputs[1] = _inputB;

    vm.startPrank(_caller);
    vm.expectEmit();
    emit V3FeeManager.FeesClaimed(
      address(pool), _caller, feeManager.FEE_RECEIVER(), _amount0, _amount1
    );
    vm.expectEmit();
    emit V3FeeManager.FeesClaimed(
      address(pool2), _caller, feeManager.FEE_RECEIVER(), _amount2, _amount3
    );
    feeManager.claimFees(_inputs);
    vm.stopPrank();

    assertEq(pool.lastParam__collectProtocol_recipient(), feeManager.FEE_RECEIVER());
    assertEq(pool2.lastParam__collectProtocol_recipient(), feeManager.FEE_RECEIVER());
    assertEq(pool.lastParam__collectProtocol_amount0Requested(), _amount0);
    assertEq(pool.lastParam__collectProtocol_amount1Requested(), _amount1);
    assertEq(pool2.lastParam__collectProtocol_amount0Requested(), _amount2);
    assertEq(pool2.lastParam__collectProtocol_amount1Requested(), _amount3);
  }

  function testFuzz_RevertIf_OnePoolInMultiplePoolCallHasInsufficientFees(
    address _caller,
    uint128 _amount0,
    uint128 _amount1,
    uint128 _amount2,
    uint128 _amount3
  ) public {
    _deployFeeManager();

    _amount0 = uint128(bound(_amount0, 1, type(uint128).max));
    _amount1 = uint128(bound(_amount1, 1, type(uint128).max));
    _amount2 = uint128(bound(_amount2, 1, type(uint128).max));
    _amount3 = uint128(bound(_amount3, 1, type(uint128).max));

    V3FeeManager.ClaimInputData memory _inputA = V3FeeManager.ClaimInputData({
      pool: pool2,
      amount0Requested: _amount0,
      amount1Requested: _amount1
    });
    V3FeeManager.ClaimInputData memory _inputB = V3FeeManager.ClaimInputData({
      pool: pool3,
      amount0Requested: _amount2,
      amount1Requested: _amount3
    });
    V3FeeManager.ClaimInputData[] memory _inputs = new V3FeeManager.ClaimInputData[](2);
    _inputs[0] = _inputA;
    _inputs[1] = _inputB;

    // Randomize which payount amount on which pool is short.
    if (_amount0 % 2 == 0) {
      pool2.setNextReturn__collectProtocol(
        _amount0 % 2 == 0 ? _amount0 : _amount0 - 1, _amount0 % 2 == 1 ? _amount1 : _amount1 - 1
      );
    } else {
      pool3.setNextReturn__collectProtocol(
        _amount2 % 2 == 0 ? _amount2 : _amount2 - 1, _amount2 % 2 == 1 ? _amount3 : _amount3 - 1
      );
    }

    vm.startPrank(_caller);
    vm.expectRevert(V3FeeManager.V3FeeManager__InsufficientFeesCollected.selector);
    feeManager.claimFees(_inputs);
    vm.stopPrank();

    // Nothing was transferred or collected.
    assertEq(pool.lastParam__collectProtocol_recipient(), address(0));
    assertEq(pool2.lastParam__collectProtocol_recipient(), address(0));
    assertEq(pool.lastParam__collectProtocol_amount0Requested(), 0);
    assertEq(pool.lastParam__collectProtocol_amount1Requested(), 0);
    assertEq(pool2.lastParam__collectProtocol_amount0Requested(), 0);
    assertEq(pool2.lastParam__collectProtocol_amount1Requested(), 0);
  }
}

contract _ClaimFees is V3FeeManagerTest {
  function testFuzz_ReturnsFeesCollected(
    address _caller,
    uint128 _amount0Requested,
    uint128 _amount1Requested,
    uint128 _amount0,
    uint128 _amount1
  ) public {
    _deployFeeManager();

    V3FeeManager.ClaimInputData memory _input = V3FeeManager.ClaimInputData({
      pool: pool,
      amount0Requested: _amount0Requested,
      amount1Requested: _amount1Requested
    });

    _amount0 = uint128(bound(_amount0, _amount0Requested, type(uint128).max));
    _amount1 = uint128(bound(_amount1, _amount1Requested, type(uint128).max));
    pool.setNextReturn__collectProtocol(_amount0, _amount1);

    vm.prank(_caller);
    V3FeeManager.ClaimOutputData memory _output = feeManager.exposed_claimFees(_input);
    vm.stopPrank();

    assertEq(address(_output.pool), address(pool));
    assertEq(_output.amount0, _amount0);
    assertEq(_output.amount1, _amount1);
  }

  function testFuzz_CollectsProtocolFeek(
    address _caller,
    uint128 _amount0Requested,
    uint128 _amount1Requested
  ) public {
    _deployFeeManager();

    vm.assume(_caller != address(0));

    V3FeeManager.ClaimInputData memory _input = V3FeeManager.ClaimInputData({
      pool: pool,
      amount0Requested: _amount0Requested,
      amount1Requested: _amount1Requested
    });

    vm.prank(_caller);
    feeManager.exposed_claimFees(_input);
    vm.stopPrank();

    assertEq(pool.lastParam__collectProtocol_recipient(), feeManager.FEE_RECEIVER());
    assertEq(pool.lastParam__collectProtocol_amount0Requested(), _amount0Requested);
    assertEq(pool.lastParam__collectProtocol_amount1Requested(), _amount1Requested);
  }

  function testFuzz_EmitsFeesClaimedEvent(
    address _caller,
    uint128 _amount0Requested,
    uint128 _amount1Requested,
    uint128 _amount0,
    uint128 _amount1
  ) public {
    _deployFeeManager();

    vm.assume(_caller != address(0));

    V3FeeManager.ClaimInputData memory _input = V3FeeManager.ClaimInputData({
      pool: pool,
      amount0Requested: _amount0Requested,
      amount1Requested: _amount1Requested
    });

    _amount0 = uint128(bound(_amount0, _amount0Requested, type(uint128).max));
    _amount1 = uint128(bound(_amount1, _amount1Requested, type(uint128).max));
    pool.setNextReturn__collectProtocol(_amount0, _amount1);

    vm.expectEmit();
    emit V3FeeManager.FeesClaimed(
      address(pool), _caller, feeManager.FEE_RECEIVER(), _amount0, _amount1
    );
    vm.prank(_caller);
    feeManager.exposed_claimFees(_input);
    vm.stopPrank();
  }

  function testFuzz_RevertIf_InsufficientFeesAvailable(
    address _caller,
    uint128 _amount0Requested,
    uint128 _amount1Requested,
    uint128 _amount0,
    uint128 _amount1
  ) public {
    _deployFeeManager();

    _amount0Requested = uint128(bound(_amount0Requested, 1, type(uint128).max));
    _amount1Requested = uint128(bound(_amount1Requested, 1, type(uint128).max));

    V3FeeManager.ClaimInputData memory _input = V3FeeManager.ClaimInputData({
      pool: pool,
      amount0Requested: _amount0Requested,
      amount1Requested: _amount1Requested
    });

    // Randomize which amount requested is too low.
    if (_amount0 % 2 == 0) _amount0 = uint128(bound(_amount0, 0, _amount0Requested - 1));
    else _amount1 = uint128(bound(_amount1, 0, _amount1Requested - 1));
    pool.setNextReturn__collectProtocol(_amount0, _amount1);

    vm.expectRevert(V3FeeManager.V3FeeManager__InsufficientFeesCollected.selector);
    vm.prank(_caller);
    feeManager.exposed_claimFees(_input);
    vm.stopPrank();
  }
}

contract _RevertIfNotAdmin is V3FeeManagerTest {
  function testFuzz_NoopIfCalledByAdmin() public {
    _deployFeeManager();

    vm.prank(admin);
    feeManager.exposed_revertIfNotAdmin();
  }

  function testFuzz_RevertIf_CalledByNonAdmin(address _notAdmin) public {
    vm.assume(_notAdmin != admin);
    _deployFeeManager();

    vm.expectRevert(V3FeeManager.V3FeeManager__Unauthorized.selector);
    vm.prank(_notAdmin);
    feeManager.exposed_revertIfNotAdmin();
  }
}
