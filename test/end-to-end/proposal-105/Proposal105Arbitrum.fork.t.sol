// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {Call} from "govkit/types/Call.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {InboxDecoder} from "govkit/bridges/decoders/InboxDecoder.sol";
import {InboxEncoder} from "govkit/bridges/InboxEncoder.sol";

import {Proposal105, buildProposal} from "../../../script/proposal-105/Proposal105.s.sol";
import {V4_FEE_ADAPTER_RECORD, chains} from "../../../script/proposal-105/params/Constants.sol";
import {rpcAlias} from "../../../script/proposal-104/params/Chains.sol";
import {checkInboxEthereum} from "../../../script/proposal-104/BridgeChecks.sol";
import {MAINNET_BLOCK} from "./Proposal105Remote.fork.t.sol";

/// @dev Arbitrum block the tests fork. The StablePairHook pools hold the fee configs that action 05
///      replaces.
uint256 constant ARBITRUM_BLOCK = 523_900_000;

/// @dev Record file these tests write, gitignored as `.records/*Test.json`.
string constant RECORD_NAME = "Proposal105ArbitrumForkTest";

/// @dev Tests for action 05, the StablePairHook fee config update, against an Arbitrum fork.
contract Proposal105ArbitrumForkTest is Test {
  Uniswap internal uniswap;
  Recorder internal recorder;

  uint256 internal arbitrumFork;
  uint256 internal mainnetFork;

  function setUp() public {
    bool shouldRun = vm.envOr("SHOULD_FORK_TEST", false);
    vm.skip(!shouldRun);

    arbitrumFork = vm.createSelectFork(rpcAlias(ChainId.Arbitrum), ARBITRUM_BLOCK);
    mainnetFork = vm.createFork(rpcAlias(ChainId.Ethereum), MAINNET_BLOCK);
    uniswap.loadLatest();
  }

  function test_preflightRemote() public {
    new Proposal105().preflightRemote(ARBITRUM_BLOCK);
  }

  /// @dev Builds the proposal on the mainnet fork with stand-in adapters, asserts that action 05's
  ///      Inbox delivers to Arbitrum and that its ticket runs from the Timelock's alias, then runs
  ///      the ticket as Arbitrum does, within its gas limit, and runs the postflight.
  function test_execute() public {
    vm.selectFork(mainnetFork);
    string memory recordPath = string.concat(".records/", RECORD_NAME, ".json");
    if (vm.exists(recordPath)) vm.removeFile(recordPath);
    recorder.initialize({scriptName: RECORD_NAME});
    uint256[5] memory list = chains();
    for (uint256 i; i < list.length; i++) {
      recorder.write(list[i], V4_FEE_ADAPTER_RECORD, address(uint160(0xC000 + i)));
    }
    (address inbox, address timelock, uint256 gasLimit,,, Call memory remoteCall) =
      InboxDecoder.decode(buildProposal(uniswap, recorder).calls[list.length]);
    checkInboxEthereum(inbox, ChainId.Arbitrum, "action");
    assertEq(timelock, uniswap.ethereum.timelock, "inbox.timelock");

    vm.selectFork(arbitrumFork);
    vm.prank(InboxEncoder.arbitrumAlias(timelock));
    (bool success, bytes memory returndata) =
      remoteCall.target.call{gas: gasLimit, value: remoteCall.value}(remoteCall.data);
    require(success, string(returndata));

    new Proposal105().postflightRemote();
  }
}
