// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {Call} from "govkit/types/Call.sol";
import {Proposal} from "govkit/types/Proposal.sol";
import {WormholeEncoder} from "govkit/bridges/WormholeEncoder.sol";
import {IWormholeSender} from "govkit/interfaces/bridges/IWormholeSender.sol";

import {ArcFees, buildProposal} from "../../../script/proposal-7/ArcFees.s.sol";
import {INttManagerPeers, IWormholeTransceiver} from "../../../script/proposal-7/Interfaces.sol";
import "../../../script/proposal-7/params/Constants.sol" as Constants;
import {ArcStandIns} from "../../utils/ArcStandIns.sol";
import {executeAsTimelock} from "../../utils/TimelockExecution.sol";

/// @dev Mainnet block the fork is pinned to. Chosen while neither Ethereum NTT contract knew Arc,
/// which `preflightEthereum` requires; the tests stay green at this block after the proposal
/// executes.
uint256 constant MAINNET_BLOCK = 25_992_796;

/// @dev Record file these tests write, gitignored as `.records/*Test.json`. Distinct from every
/// other test's record so parallel test contracts never write the same file.
string constant RECORD_NAME = "ArcEthereumTest";

/// @dev Tests for the Ethereum half of the proposal, against a mainnet fork.
contract ArcFeesEthereumForkTest is Test {
  Uniswap internal uniswap;
  Recorder internal recorder;

  function setUp() public {
    vm.createSelectFork("mainnet", MAINNET_BLOCK);
    uniswap.loadLatest();
  }

  function test_preflightEthereum() public {
    new ArcFees().preflightEthereum(MAINNET_BLOCK);
  }

  /// @dev Executes all three actions as the Timelock and asserts the peers they registered on the
  /// real NTT contracts and the message they published from the real sender.
  function test_execute() public {
    // Stand-in Arc addresses: the peer registrations only require them to be non-zero.
    ArcStandIns.writeRecord(recorder, RECORD_NAME);

    Proposal memory proposal = buildProposal(uniswap, recorder);
    Call[] memory calls = proposal.calls;

    address timelock = uniswap.ethereum.timelock;
    uint16 arcWormholeChainId = Constants.Arc.WORMHOLE_CHAIN_ID;
    IWormholeTransceiver transceiver = IWormholeTransceiver(uniswap.ethereum.wormholeTransceiver);
    INttManagerPeers nttManager = INttManagerPeers(uniswap.ethereum.nttManager);

    // Execute the proposal as the Timelock, recording what it emits.
    vm.recordLogs();
    executeAsTimelock(vm, timelock, calls);
    Vm.Log[] memory logs = vm.getRecordedLogs();

    // Assert action 02 reached the Wormhole sender and published a message addressed to the Arc
    // receiver: exactly one `MessageSent` from the sender, with the receiver as its indexed
    // argument. The payload is not compared.
    uint256 sent;
    for (uint256 i; i < logs.length; i++) {
      if (logs[i].emitter != Constants.Ethereum.WORMHOLE_SENDER) continue;
      if (logs[i].topics[0] != IWormholeSender.MessageSent.selector) continue;
      // An indexed address is left-padded to the 32-byte topic.
      if (logs[i].topics[1] != bytes32(uint256(uint160(Constants.Arc.WORMHOLE_RECEIVER)))) {
        continue;
      }
      sent++;
    }
    assertEq(sent, 1, "MessageSent.count");

    // Assert actions 00 and 01 registered the Arc Wormhole contracts as peers with UNI's decimals.
    assertEq(
      transceiver.getWormholePeer(arcWormholeChainId),
      WormholeEncoder.toWormholeFormat(ArcStandIns.WORMHOLE_TRANSCEIVER),
      "wormholeTransceiver.peer"
    );

    INttManagerPeers.NttManagerPeer memory peer = nttManager.getPeer(arcWormholeChainId);
    assertEq(
      peer.peerAddress, WormholeEncoder.toWormholeFormat(ArcStandIns.NTT_MANAGER), "nttManager.peer"
    );
    assertEq(peer.tokenDecimals, 18, "nttManager.peer.decimals");
  }
}
