// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";

import {Call} from "govkit/types/Call.sol";

import {
  buildUpgradeVolatileHookCall
} from "../../../../script/proposal-103/volatile-hook/UpgradeVolatileHook.s.sol";
import {VolatileHook} from "../../../../script/proposal-103/volatile-hook/Constants.sol";
import {IVolatilePairHook} from "../../../../script/proposal-103/volatile-hook/Interfaces.sol";

/// @dev Unit tests for the upgrade's encoding.
contract UpgradeVolatileHookTest is Test {
  /// @dev Asserts the action is one call to the proxy, with exactly
  /// `upgradeToAndCall(NEW_IMPLEMENTATION, "")` and no value.
  function test_buildUpgradeVolatileHookCall() public pure {
    Call memory call = buildUpgradeVolatileHookCall();

    assertEq(call.target, VolatileHook.PROXY, "call.target");
    assertEq(call.value, 0, "call.value");
    assertEq(
      call.data,
      abi.encodeWithSelector(
        IVolatilePairHook.upgradeToAndCall.selector, VolatileHook.NEW_IMPLEMENTATION, bytes("")
      ),
      "call.data"
    );
  }
}
