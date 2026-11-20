// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

import {V4FeeAdapter} from "../../src/feeAdapters/V4FeeAdapter.sol";

/// @dev One pool of a fixture file and the protocol fee it should have after the proposal.
struct FixturePool {
  address currency0;
  address currency1;
  uint24 fee;
  int24 tickSpacing;
  address hooks;
  /// @dev "unchanged" for the fee the pool has before the proposal, "reverts" for a pool whose
  ///      fee computation reverts, or the fee in pips as a decimal string.
  string expected;
}

/// @dev Base of the fork tests that check pool fees against a fixture file. Each fixture lists the
///      pools of every hook the policy assigns a ruleset to, the pools of the hooks it leaves out,
///      a hookless pool for each LP fee, and a sample of other hooked pools. We generated the
///      fixtures from a scan of each chain's PoolManager `Initialize` events, with each expected
///      fee calculated from the fee targets and the hookless curve, independently of the
///      rulesets.
abstract contract V4FeeFixtureTest is Test {
  using StateLibrary for *;
  using PoolIdLibrary for PoolKey;

  /// @dev The fixture's pools, read by {_loadFixture}.
  FixturePool[] internal fixturePools;

  /// @dev Each pool's fee before the proposal, read by {_readFeesBefore}: the adapter's fee for
  ///      pools expected to keep it, and the PoolManager's stored fee for pools whose fee
  ///      computation reverts.
  mapping(uint256 index => uint24) internal feesBefore;

  /// @dev Reads the fixture at `path` into `fixturePools`, and returns its block.
  function _loadFixture(string memory path) internal returns (uint256 blockNumber) {
    string memory json = vm.readFile(path);
    blockNumber = vm.parseJsonUint(json, ".block");
    FixturePool[] memory pools = abi.decode(
      vm.parseJsonTypeArray(
        json,
        ".pools",
        "FixturePool(address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks,string expected)"
      ),
      (FixturePool[])
    );
    for (uint256 i; i < pools.length; i++) {
      fixturePools.push(pools[i]);
    }
  }

  /// @dev Records the fee that `adapter` gives each pool expected to keep its fee, and the
  ///      PoolManager's stored fee for each pool whose fee computation is expected to revert.
  function _readFeesBefore(V4FeeAdapter adapter) internal {
    for (uint256 i; i < fixturePools.length; i++) {
      if (_is(fixturePools[i].expected, "unchanged")) feesBefore[i] = adapter.getFee(_key(i));
      if (_is(fixturePools[i].expected, "reverts")) feesBefore[i] = _storedFee(adapter, i);
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
        assertEq(_storedFee(adapter, i), feesBefore[i], _label("storedFee", i));
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

  /// @dev Returns the protocol fee the PoolManager stores for pool `index`.
  function _storedFee(V4FeeAdapter adapter, uint256 index) internal view returns (uint24 fee) {
    (,, fee,) = adapter.POOL_MANAGER().getSlot0(_key(index).toId());
  }

  /// @dev Returns the fee pool `index` should have after the proposal.
  function _expectedFee(uint256 index) internal view returns (uint24) {
    string memory expected = fixturePools[index].expected;
    if (_is(expected, "unchanged")) return feesBefore[index];
    return uint24(vm.parseUint(expected));
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
