// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";

import {Proposal105, buildProposal} from "../../../script/proposal-105/Proposal105.s.sol";
import {
  V4_FEE_ADAPTER_RECORD,
  chains,
  l1Messenger
} from "../../../script/proposal-105/params/Constants.sol";
import {v4Accounts} from "../../../script/proposal-104/params/Chains.sol";
import {executeAsTimelock} from "../../utils/TimelockExecution.sol";
import {countOPStackSentMessages} from "../../utils/OPStackSentMessages.sol";
import {MAINNET_BLOCK} from "./Proposal105Remote.fork.t.sol";

/// @dev Record file these tests write, gitignored as `.records/*Test.json`.
string constant RECORD_NAME = "Proposal105EthereumForkTest";

/// @dev Tests for the whole proposal executing on Ethereum, with stand-in adapters. The remote
///      tests cover each chain's side.
contract Proposal105EthereumForkTest is Test {
  Uniswap internal uniswap;
  Recorder internal recorder;

  function setUp() public {
    bool shouldRun = vm.envOr("SHOULD_FORK_TEST", false);
    vm.skip(!shouldRun);

    vm.createSelectFork("mainnet", MAINNET_BLOCK);
    uniswap.loadLatest();

    string memory recordPath = string.concat(".records/", RECORD_NAME, ".json");
    if (vm.exists(recordPath)) vm.removeFile(recordPath);
    recorder.initialize({scriptName: RECORD_NAME});
    uint256[5] memory list = chains();
    for (uint256 i; i < list.length; i++) {
      recorder.write(list[i], V4_FEE_ADAPTER_RECORD, address(uint160(0xC000 + i)));
    }
  }

  function test_preflightEthereum() public {
    new Proposal105().preflightEthereum(MAINNET_BLOCK);
  }

  /// @dev Executes the proposal as the Timelock and asserts that each action sends one message,
  ///      through its chain's L1CrossDomainMessenger to its CrossChainAccount.
  function test_execute() public {
    vm.recordLogs();
    executeAsTimelock(vm, uniswap.ethereum.timelock, buildProposal(uniswap, recorder).calls);
    Vm.Log[] memory logs = vm.getRecordedLogs();

    uint256[5] memory list = chains();
    for (uint256 i; i < list.length; i++) {
      assertEq(
        countOPStackSentMessages(
          logs, l1Messenger(uniswap, list[i]), v4Accounts(uniswap, list[i]).governanceExecutor
        ),
        1,
        string.concat("SentMessage ", vm.toString(list[i]))
      );
    }
  }
}
