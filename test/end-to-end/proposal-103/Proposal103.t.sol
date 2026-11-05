// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {Call} from "govkit/types/Call.sol";
import {Proposal} from "govkit/types/Proposal.sol";

import {buildProposal} from "../../../script/proposal-103/Proposal103.s.sol";
import {
  buildReplaceReleaserCall
} from "../../../script/proposal-103/x-layer/ReplaceXLayerReleaser.s.sol";
import {
  buildUpgradeVolatileHookCall
} from "../../../script/proposal-103/volatile-hook/UpgradeVolatileHook.s.sol";
import {XLayerStandIns} from "../../utils/XLayerStandIns.sol";

/// @dev Record file these tests write, gitignored as `.records/*Test.json`.
string constant RECORD_NAME = "Proposal103Test";

/// @dev Unit tests for how the proposal joins its actions. Each action's folder tests its encoding.
contract Proposal103Test is Test {
  Uniswap internal uniswap;
  Recorder internal recorder;

  function setUp() public {
    uniswap.loadLatest();
    XLayerStandIns.writeRecord(recorder, RECORD_NAME);
  }

  /// @dev Asserts the proposal is exactly the hook upgrade, then the X Layer action.
  function test_buildProposal() public view {
    Proposal memory proposal = buildProposal(uniswap, recorder);

    assertEq(proposal.calls.length, 2, "calls.length");
    _assertEq(proposal.calls[0], buildUpgradeVolatileHookCall(), "calls[0]");
    _assertEq(proposal.calls[1], buildReplaceReleaserCall(uniswap, recorder), "calls[1]");
  }

  /// @dev Asserts `actual` and `expected` are the same call.
  function _assertEq(Call memory actual, Call memory expected, string memory label) internal pure {
    assertEq(keccak256(abi.encode(actual)), keccak256(abi.encode(expected)), label);
  }
}
