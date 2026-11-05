// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {Call, LibCall} from "govkit/types/Call.sol";
import {
  ICrossDomainMessenger
} from "@eth-optimism-bedrock/interfaces/universal/ICrossDomainMessenger.sol";

import {
  ReplaceXLayerReleaser,
  buildReplaceReleaserCall
} from "../../../../script/proposal-103/x-layer/ReplaceXLayerReleaser.s.sol";
import {executeAsTimelock} from "../../../utils/TimelockExecution.sol";
import {XLayerStandIns} from "../../../utils/XLayerStandIns.sol";

/// @dev Mainnet block the fork is pinned to. Any block where X Layer's L1CrossDomainMessenger is
/// live and unpaused satisfies `preflightEthereum`.
uint256 constant MAINNET_BLOCK = 26_105_508;

/// @dev Record file these tests write, gitignored as `.records/*Test.json`. The Ethereum side does
/// not read the new releaser, so a stand-in serves.
string constant RECORD_NAME = "ReplaceXLayerReleaserEthereumTest";

/// @dev Tests for the Ethereum side of the proposal, against a mainnet fork.
contract ReplaceXLayerReleaserEthereumForkTest is Test {
  Uniswap internal uniswap;
  Recorder internal recorder;

  function setUp() public {
    bool shouldRun = vm.envOr("SHOULD_FORK_TEST", false);
    vm.skip(!shouldRun);

    vm.createSelectFork("mainnet", MAINNET_BLOCK);
    uniswap.loadLatest();
    XLayerStandIns.writeRecord(recorder, RECORD_NAME);
  }

  function test_preflightEthereum() public {
    new ReplaceXLayerReleaser().preflightEthereum(MAINNET_BLOCK);
  }

  /// @dev Executes the X Layer action as the Timelock and asserts it sent exactly one message
  /// through X Layer's real L1CrossDomainMessenger, addressed to the X Layer CrossChainAccount. The
  /// message is not compared here; the X Layer fork test relays it and asserts its effect.
  function test_execute() public {
    Call[] memory calls = LibCall.newCalls([buildReplaceReleaserCall(uniswap, recorder)]);

    // Execute the proposal as the Timelock, recording what it emits.
    vm.recordLogs();
    executeAsTimelock(vm, uniswap.ethereum.timelock, calls);
    Vm.Log[] memory logs = vm.getRecordedLogs();

    // Asserts the action results in a single `SentMessage` event from X Layer's messenger, with
    // the CrossChainAccount as the indexed target.
    uint256 sent;
    for (uint256 i; i < logs.length; i++) {
      if (logs[i].emitter != uniswap.ethereum.bridge.xLayer) continue;
      if (logs[i].topics[0] != ICrossDomainMessenger.SentMessage.selector) continue;
      // An indexed address is left-padded to the 32-byte topic.
      if (logs[i].topics[1] != bytes32(uint256(uint160(uniswap.xLayer.crossChainAccount)))) {
        continue;
      }
      sent++;
    }
    assertEq(sent, 1, "SentMessage.count");
  }
}
