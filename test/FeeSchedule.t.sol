// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";

import {FeeSchedule} from "../script/shared/FeeSchedule.sol";

contract FeeScheduleTest is Test {
  function test_aggHookFeeValue_knownValues() public pure {
    // 1000 pips (10 bps) is the proposal 6 aggregator default: 40 per direction.
    assertEq(FeeSchedule.aggHookFeeValue(1000), 40 << 12 | 40);
    // 300 pips is the proposal 6 stable-stable fee: 12 per direction.
    assertEq(FeeSchedule.aggHookFeeValue(300), 12 << 12 | 12);
    // 100 pips is Base's stable-stable fee: 4 per direction.
    assertEq(FeeSchedule.aggHookFeeValue(100), 4 << 12 | 4);
    assertEq(FeeSchedule.aggHookFeeValue(0), 0);
  }

  function test_aggHookFeeValue_capIsThePoolManagerCap() public pure {
    uint24 atCap = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE) * FeeSchedule.AGG_HOOK_FEE_MULTIPLIER;
    uint24 value = FeeSchedule.aggHookFeeValue(atCap);
    assertEq(value & 0xfff, ProtocolFeeLibrary.MAX_PROTOCOL_FEE);
    assertTrue(ProtocolFeeLibrary.isValidProtocolFee(value));
  }

  function test_aggHookFeeValue_aboveCapReverts() public {
    uint24 aboveCap =
      (uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE) + 1) * FeeSchedule.AGG_HOOK_FEE_MULTIPLIER;
    vm.expectRevert(bytes("FeeSchedule: fee above the v4 cap"));
    this.aggHookFeeValue(aboveCap);
  }

  function test_aggHookFeeValue_inexactDivisionReverts() public {
    vm.expectRevert(bytes("FeeSchedule: fee not a multiple of 25 pips"));
    this.aggHookFeeValue(310);
  }

  function testFuzz_aggHookFeeValue_isValidAndRoundTrips(uint24 perDirection) public pure {
    perDirection = uint24(bound(perDirection, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
    uint24 value = FeeSchedule.aggHookFeeValue(perDirection * FeeSchedule.AGG_HOOK_FEE_MULTIPLIER);
    assertTrue(ProtocolFeeLibrary.isValidProtocolFee(value));
    assertEq(value & 0xfff, perDirection);
    assertEq(value >> 12, perDirection);
  }

  function testFuzz_aggHookFeeValue_rejectsEveryInexactFee(uint24 feePips) public {
    feePips = uint24(bound(feePips, 0, 25_000));
    vm.assume(feePips % FeeSchedule.AGG_HOOK_FEE_MULTIPLIER != 0);
    vm.expectRevert(bytes("FeeSchedule: fee not a multiple of 25 pips"));
    this.aggHookFeeValue(feePips);
  }

  function aggHookFeeValue(uint24 feePips) external pure returns (uint24) {
    return FeeSchedule.aggHookFeeValue(feePips);
  }
}
