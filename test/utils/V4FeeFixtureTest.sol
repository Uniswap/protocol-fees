// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

import {V4FeeAdapter} from "../../src/feeAdapters/V4FeeAdapter.sol";

/// @dev One pool of a fixture file, its protocol fee before the proposal and the protocol fee it
///      should have after. Fees are in the PoolManager's packed form: the zero-for-one fee in pips
///      in the low 12 bits and the one-for-zero fee in the next 12, so 49164 is 12 pips each way.
struct FixturePool {
  address currency0;
  address currency1;
  uint24 fee;
  int24 tickSpacing;
  address hooks;
  /// @dev The fee the chain's fee controller sets at the fixture block, as {_feeBefore} reads it.
  uint24 before;
  /// @dev The fee after the proposal as a decimal string, or "reverts" for a pool whose fee
  ///      computation reverts.
  string expected;
}

/// @dev Base of the fork tests that check pool fees against a fixture file. Each fixture lists
///      every pool with a hook the policy assigns a ruleset to, up to 20 pools with each hook it
///      leaves out, a hookless pool for each LP fee, and a sample of other hooked pools, from a
///      scan of each chain's PoolManager `Initialize` events. We read each `before` from the
///      chain, and calculated each changed `expected` fee from the parameter file's fee levels, the
///      hookless curve and each pair hook's `feeConfig`, in a model separate from the rulesets.
abstract contract V4FeeFixtureTest is Test {
  using StateLibrary for *;
  using PoolIdLibrary for PoolKey;

  /// @dev The fixture's pools, read by {_loadFixture}.
  FixturePool[] internal fixturePools;

  /// @dev The PoolManager's stored fee before the proposal for each pool whose fee computation
  ///      reverts, read by {_readStoredFeesBefore}.
  mapping(uint256 index => uint24) internal storedFeesBefore;

  /// @dev Returns the fee the chain's fee controller sets for pool `index` before the proposal.
  function _feeBefore(uint256 index) internal view virtual returns (uint24);

  /// @dev Reads the fixture at `path` into `fixturePools`, and returns its block.
  function _loadFixture(string memory path) internal returns (uint256 blockNumber) {
    string memory json = vm.readFile(path);
    blockNumber = vm.parseJsonUint(json, ".block");
    FixturePool[] memory pools = abi.decode(
      vm.parseJsonTypeArray(
        json,
        ".pools",
        "FixturePool(address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks,uint24 before,string expected)"
      ),
      (FixturePool[])
    );
    for (uint256 i; i < pools.length; i++) {
      fixturePools.push(pools[i]);
    }
  }

  /// @dev Asserts that each pool's `before` is the fee the chain's fee controller sets for it.
  function _assertFeesBefore() internal view {
    for (uint256 i; i < fixturePools.length; i++) {
      assertEq(_feeBefore(i), fixturePools[i].before, _label("before", i));
    }
  }

  /// @dev Records the PoolManager's stored fee for each pool whose fee computation is expected to
  ///      revert.
  function _readStoredFeesBefore(V4FeeAdapter adapter) internal {
    for (uint256 i; i < fixturePools.length; i++) {
      if (_is(fixturePools[i].expected, "reverts")) storedFeesBefore[i] = _storedFee(adapter, i);
    }
  }

  /// @dev Asserts that `adapter` gives each pool its expected fee, then pushes the fees of the
  ///      pools whose fee computation does not revert to the PoolManager, and asserts each pool's
  ///      protocol fee there. For a pool whose fee computation reverts, asserts that a fee update
  ///      reverts and the PoolManager keeps the fee it stored before the proposal.
  function _assertFees(V4FeeAdapter adapter) internal {
    PoolKey[] memory keys = new PoolKey[](fixturePools.length);
    uint256[] memory indexes = new uint256[](fixturePools.length);
    uint256 count;
    for (uint256 i; i < fixturePools.length; i++) {
      if (_is(fixturePools[i].expected, "reverts")) {
        vm.expectRevert();
        adapter.triggerFeeUpdate(_key(i));
        assertEq(_storedFee(adapter, i), storedFeesBefore[i], _label("storedFee", i));
        continue;
      }
      assertEq(adapter.getFee(_key(i)), _expectedFee(i), _label("getFee", i));
      keys[count] = _key(i);
      indexes[count] = i;
      count++;
    }

    assembly ("memory-safe") {
      mstore(keys, count)
    }
    adapter.batchTriggerFeeUpdate(keys);

    for (uint256 i; i < count; i++) {
      assertEq(
        _storedFee(adapter, indexes[i]), _expectedFee(indexes[i]), _label("protocolFee", indexes[i])
      );
    }
  }

  /// @dev Returns the protocol fee the PoolManager of `adapter` stores for pool `index`.
  function _storedFee(V4FeeAdapter adapter, uint256 index) internal view returns (uint24) {
    return _storedFee(adapter.POOL_MANAGER(), index);
  }

  /// @dev Returns the protocol fee `poolManager` stores for pool `index`.
  function _storedFee(IPoolManager poolManager, uint256 index) internal view returns (uint24 fee) {
    (,, fee,) = poolManager.getSlot0(_key(index).toId());
  }

  /// @dev Returns the fee pool `index` should have after the proposal.
  function _expectedFee(uint256 index) internal view returns (uint24) {
    return uint24(vm.parseUint(fixturePools[index].expected));
  }

  /// @dev Returns the key of pool `index`.
  function _key(uint256 index) internal view returns (PoolKey memory) {
    FixturePool storage pool = fixturePools[index];
    return PoolKey({
      currency0: Currency.wrap(pool.currency0),
      currency1: Currency.wrap(pool.currency1),
      fee: pool.fee,
      tickSpacing: pool.tickSpacing,
      hooks: IHooks(pool.hooks)
    });
  }

  /// @dev Returns whether `a` equals `b`.
  function _is(string memory a, string memory b) internal pure returns (bool) {
    return keccak256(bytes(a)) == keccak256(bytes(b));
  }

  /// @dev Returns an assertion label naming the pool `index` and its hook.
  function _label(string memory what, uint256 index) internal view returns (string memory) {
    return string.concat(
      what, " pool ", vm.toString(index), " hook ", vm.toString(fixturePools[index].hooks)
    );
  }
}
