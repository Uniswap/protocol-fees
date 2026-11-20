// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {Proposal} from "govkit/types/Proposal.sol";
import {IInbox} from "govkit/interfaces/bridges/IInbox.sol";
import {IFxRoot} from "govkit/interfaces/bridges/IFxRoot.sol";
import {ChainId} from "govkit/constants/ChainId.sol";

import {
  IWormhole as IWormholeCore
} from "lib/native-token-transfers/evm/lib/wormhole-solidity-sdk/src/interfaces/IWormhole.sol";

import {IV4FeeAdapter} from "../../../src/interfaces/IV4FeeAdapter.sol";
import {Proposal104, buildProposal} from "../../../script/proposal-104/Proposal104.s.sol";
import {Records, v4FeeAdapter} from "../../../script/proposal-104/params/Constants.sol";
import {executeAsTimelock} from "../../utils/TimelockExecution.sol";
import {countOPStackSentMessages} from "../../utils/OPStackSentMessages.sol";
import {MAINNET_BLOCK, StateSynced, proposalChains} from "./Proposal104Remote.fork.t.sol";

/// @dev Record file these tests write, gitignored as `.records/*Test.json`.
string constant RECORD_NAME = "Proposal104EthereumForkTest";

/// @dev Tests for the whole proposal executing on Ethereum, with stand-in policies. The remote
///      tests cover each chain's side.
contract Proposal104EthereumForkTest is Test {
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
    uint256[8] memory chains = proposalChains();
    for (uint256 i; i < chains.length; i++) {
      recorder.write(chains[i], Records.V4_FEE_POLICY, _standIn(i));
    }
  }

  function test_preflightEthereum() public {
    new Proposal104().preflightEthereum(MAINNET_BLOCK);
  }

  /// @dev Executes the proposal as the Timelock and asserts the Ethereum adapter's new policy, and
  ///      that each other action sends one message through its chain's route.
  function test_execute() public {
    Proposal memory proposal = buildProposal(uniswap, recorder);
    vm.deal(uniswap.ethereum.timelock, _value(proposal));

    vm.recordLogs();
    executeAsTimelock(vm, uniswap.ethereum.timelock, proposal.calls);
    Vm.Log[] memory logs = vm.getRecordedLogs();

    assertEq(
      address(IV4FeeAdapter(v4FeeAdapter(ChainId.Ethereum)).policy()),
      _standIn(0),
      "ethereum.adapter.policy"
    );
    assertEq(
      _count(logs, uniswap.ethereum.bridge.arbitrum, IInbox.InboxMessageDelivered.selector),
      1,
      "arbitrum.InboxMessageDelivered"
    );
    assertEq(
      countOPStackSentMessages(logs, uniswap.ethereum.bridge.base, uniswap.base.crossChainAccount),
      1,
      "base.SentMessage"
    );
    assertEq(
      countOPStackSentMessages(
        logs, uniswap.ethereum.bridge.optimism, uniswap.optimism.crossChainAccount
      ),
      1,
      "optimism.SentMessage"
    );
    assertEq(
      _count(
        logs, uniswap.ethereum.bridge.wormholeCore, IWormholeCore.LogMessagePublished.selector
      ),
      2,
      "bnbChainAndArc.LogMessagePublished"
    );
    assertEq(
      _count(logs, IFxRoot(uniswap.ethereum.bridge.polygon).stateSender(), StateSynced.selector),
      1,
      "polygon.StateSynced"
    );
    assertEq(
      _count(logs, uniswap.ethereum.bridge.robinhood, IInbox.InboxMessageDelivered.selector),
      1,
      "robinhood.InboxMessageDelivered"
    );
  }

  /// @dev Returns the stand-in policy of the chain at `index` in `proposalChains`.
  function _standIn(uint256 index) internal pure returns (address) {
    return address(uint160(0xB000 + index));
  }

  /// @dev Returns the sum of the values of `proposal`'s calls.
  function _value(Proposal memory proposal) internal pure returns (uint256 value) {
    for (uint256 i; i < proposal.calls.length; i++) {
      value += proposal.calls[i].value;
    }
  }

  /// @dev Returns how many events with signature `selector` `emitter` emitted in `logs`.
  function _count(Vm.Log[] memory logs, address emitter, bytes32 selector)
    internal
    pure
    returns (uint256 count)
  {
    for (uint256 i; i < logs.length; i++) {
      if (logs[i].emitter == emitter && logs[i].topics[0] == selector) count++;
    }
  }
}
