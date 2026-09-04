// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";

import {Uniswap} from "govkit/types/Uniswap.sol";
import {Call} from "govkit/types/Call.sol";

import {RotateEarnSentinels} from "../../../script/proposal-8/RotateEarnSentinels.s.sol";

contract RotateEarnSentinelsForkTest is Test {
  Uniswap internal uniswap;
  RotateEarnSentinels internal script;

  function setUp() public {
    vm.createSelectFork("mainnet", 25_904_682);
    uniswap.loadLatest();
    script = new RotateEarnSentinels();
  }

  /// @dev Preflight: the script's own precondition check holds at the pinned block.
  function test_preflight_state() public {
    script.preflight();
  }

  /// @dev Postflight: the proposal's calls, sent by the Timelock, flip exactly the intended flags.
  function test_execute_as_timelock() public {
    // Get the proposal's calls
    Call[] memory calls = script.proposal().calls;
    assertEq(calls.length, 6);

    vm.startPrank(uniswap.ethereum.timelock);
    // Execute the proposal's calls
    for (uint256 i; i < calls.length; i++) {
      (bool ok,) = calls[i].target.call{value: calls[i].value}(calls[i].data);
      assertTrue(ok);
    }
    vm.stopPrank();

    // Check that the sentinels are set as intended
    script.postflight();
  }
}
