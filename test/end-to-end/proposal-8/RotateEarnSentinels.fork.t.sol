// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";

import {Uniswap} from "govkit/types/Uniswap.sol";
import {Call} from "govkit/types/Call.sol";

import {
  RotateEarnSentinels,
  buildProposal
} from "../../../script/proposal-8/RotateEarnSentinels.s.sol";
import {executeAsTimelock} from "../../utils/TimelockExecution.sol";

/// @dev Mainnet block the fork is pinned to. Chosen while every vault still had its legacy
/// sentinel and none had its new one, which `preflight` requires; the tests stay green at this
/// block after the proposal executes.
uint256 constant MAINNET_BLOCK = 25_904_682;

contract RotateEarnSentinelsForkTest is Test {
  Uniswap internal uniswap;
  RotateEarnSentinels internal script;

  function setUp() public {
    vm.createSelectFork("mainnet", MAINNET_BLOCK);
    uniswap.loadLatest();
    script = new RotateEarnSentinels();
  }

  function test_preflight() public view {
    script.preflight(MAINNET_BLOCK);
  }

  /// @dev Executes the proposal as the Timelock and asserts the outcome the script checks after
  /// execution onchain.
  function test_execute() public {
    Call[] memory calls = buildProposal(uniswap).calls;
    assertEq(calls.length, 6, "calls.length");

    executeAsTimelock(vm, uniswap.ethereum.timelock, calls);

    script.postflight();
  }
}
