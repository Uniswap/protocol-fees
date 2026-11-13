// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {Proposal} from "govkit/types/Proposal.sol";

import {Proposal103, buildProposal} from "../../../script/proposal-103/Proposal103.s.sol";
import {
  UpgradeVolatileHook
} from "../../../script/proposal-103/volatile-hook/UpgradeVolatileHook.s.sol";
import {executeAsTimelock} from "../../utils/TimelockExecution.sol";
import {XLayerStandIns} from "../../utils/XLayerStandIns.sol";
import {countOPStackSentMessages} from "../../utils/OPStackSentMessages.sol";

/// @dev After the new implementation's deployment at block 26_347_359.
uint256 constant MAINNET_BLOCK = 26_349_000;

/// @dev Record file these tests write, gitignored as `.records/*Test.json`. The Ethereum side does
/// not read the new releaser, so a stand-in serves.
string constant RECORD_NAME = "Proposal103ForkTest";

/// @dev Tests for the whole proposal executing on Ethereum. Each action's directory covers that
/// action in more depth, including the X Layer message's effect on X Layer.
contract Proposal103ForkTest is Test {
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
    new Proposal103().preflightEthereum();
  }

  /// @dev Executes the whole proposal as the Timelock and asserts both actions took effect.
  function test_execute() public {
    Proposal memory proposal = buildProposal(uniswap, recorder);

    vm.recordLogs();
    executeAsTimelock(vm, uniswap.ethereum.timelock, proposal.calls);
    Vm.Log[] memory logs = vm.getRecordedLogs();

    // Assert the hook runs the new implementation
    new UpgradeVolatileHook().postflightEthereum();

    // Assert X Layer's messenger sent a single message, to the CrossChainAccount
    assertEq(
      countOPStackSentMessages(
        logs, uniswap.ethereum.bridge.xLayer, uniswap.xLayer.crossChainAccount
      ),
      1,
      "SentMessage.count"
    );
  }
}
