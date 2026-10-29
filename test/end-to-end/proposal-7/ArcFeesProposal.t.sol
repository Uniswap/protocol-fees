// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {Call} from "govkit/types/Call.sol";
import {Proposal} from "govkit/types/Proposal.sol";
import {WormholeEncoder} from "govkit/bridges/WormholeEncoder.sol";
import {IWormholeSender} from "govkit/interfaces/bridges/IWormholeSender.sol";
import {IUniswapV2Factory} from "govkit/interfaces/IUniswapV2Factory.sol";
import {IUniswapV3Factory} from "govkit/interfaces/IUniswapV3Factory.sol";
import {IPoolManager} from "govkit/interfaces/IPoolManager.sol";

import {buildProposal, encodeWormhole} from "../../../script/proposal-7/ArcFees.s.sol";
import {
  INttManagerPeers,
  IWormhole,
  IWormholeTransceiver
} from "../../../script/proposal-7/Interfaces.sol";
import "../../../script/proposal-7/params/Constants.sol" as Constants;
import {WormholeDecode} from "../../utils/WormholeDecode.sol";
import {ArcStandIns} from "../../utils/ArcStandIns.sol";

/// @dev Record file these tests write, gitignored as `.records/*Test.json`.
string constant RECORD_NAME = "ArcProposalTest";

/// @dev Unit tests for the proposal's encoding.
contract ArcFeesProposalTest is Test {
  Uniswap internal uniswap;
  Recorder internal recorder;

  /// @dev Non-zero so the test can tell the fee reached the two payable actions.
  uint256 internal constant MESSAGE_FEE = 7;

  function setUp() public {
    uniswap.loadLatest();
  }

  // -- encodeWormhole ---------------------------------------------------------------------------

  /// @dev Asserts that the encoder used to build the proposal is decoded correctly by
  ///      the decoder helper.
  function test_fuzz_encodeWormhole_roundTrip(Call[] memory remoteCalls, uint256 value)
    public
    pure
  {
    Call memory encoded = encodeWormhole(remoteCalls, value);

    assertEq(encoded.target, Constants.Ethereum.WORMHOLE_SENDER);
    assertEq(encoded.value, value);
    assertEq(bytes4(encoded.data), IWormholeSender.sendMessage.selector);

    (
      address sourceSender,
      address remoteReceiver,
      uint16 wormholeChainId,
      uint256 decodedValue,
      Call[] memory decodedCalls
    ) = WormholeDecode.decode(encoded);

    assertEq(sourceSender, Constants.Ethereum.WORMHOLE_SENDER);
    assertEq(remoteReceiver, Constants.Arc.WORMHOLE_RECEIVER);
    assertEq(wormholeChainId, Constants.Arc.WORMHOLE_CHAIN_ID);
    assertEq(decodedValue, value);
    _assertCallsEq(decodedCalls, remoteCalls);
  }

  // -- buildProposal ----------------------------------------------------------------------------

  /// @dev Asserts that the proposal built from the record is decoded correctly by the decoder
  ///      helper.
  function test_buildProposal() public {
    // Write the fake Arc deployment under the keys `buildProposal` reads.
    ArcStandIns.writeRecord(recorder, RECORD_NAME);

    vm.mockCall(
      uniswap.ethereum.bridge.wormholeCore,
      abi.encodeCall(IWormhole.messageFee, ()),
      abi.encode(MESSAGE_FEE)
    );

    Proposal memory proposal = buildProposal(uniswap, recorder);

    assertEq(proposal.calls.length, 3);

    // Assert action 00 registers the Arc transceiver on the Ethereum transceiver and carries the
    // fee.
    assertEq(proposal.calls[0].target, uniswap.ethereum.wormholeTransceiver);
    assertEq(proposal.calls[0].value, MESSAGE_FEE);
    assertEq(
      proposal.calls[0].data,
      abi.encodeCall(
        IWormholeTransceiver.setWormholePeer,
        (
          Constants.Arc.WORMHOLE_CHAIN_ID,
          WormholeEncoder.toWormholeFormat(ArcStandIns.WORMHOLE_TRANSCEIVER)
        )
      )
    );

    // Assert action 01 registers the Arc manager on the Ethereum manager with 18 decimals and no
    // inbound limit.
    assertEq(proposal.calls[1].target, uniswap.ethereum.nttManager);
    assertEq(proposal.calls[1].value, 0);
    assertEq(
      proposal.calls[1].data,
      abi.encodeCall(
        INttManagerPeers.setPeer,
        (
          Constants.Arc.WORMHOLE_CHAIN_ID,
          WormholeEncoder.toWormholeFormat(ArcStandIns.NTT_MANAGER),
          18,
          0
        )
      )
    );

    // Assert action 02 is one Wormhole message to the Arc receiver, carrying the fee and the
    // three fee switches.
    (
      address sourceSender,
      address remoteReceiver,
      uint16 wormholeChainId,
      uint256 value,
      Call[] memory remoteCalls
    ) = WormholeDecode.decode(proposal.calls[2]);

    assertEq(sourceSender, Constants.Ethereum.WORMHOLE_SENDER);
    assertEq(remoteReceiver, Constants.Arc.WORMHOLE_RECEIVER);
    assertEq(wormholeChainId, Constants.Arc.WORMHOLE_CHAIN_ID);
    assertEq(value, MESSAGE_FEE);
    // Assert that the three remote calls are the three fee switches.
    _assertCallsEq(remoteCalls, _expectedRemoteCalls());
  }

  // -- helpers ----------------------------------------------------------------------------------

  /// @dev Returns the three remote calls action 02 must carry, in order.
  function _expectedRemoteCalls() internal pure returns (Call[] memory calls) {
    calls = new Call[](3);
    calls[0] = Call({
      target: Constants.Arc.V2_FACTORY,
      value: 0,
      data: abi.encodeCall(IUniswapV2Factory.setFeeTo, (ArcStandIns.TOKEN_JAR))
    });
    calls[1] = Call({
      target: Constants.Arc.V3_FACTORY,
      value: 0,
      data: abi.encodeCall(IUniswapV3Factory.setOwner, (ArcStandIns.V3_OPEN_FEE_ADAPTER))
    });
    calls[2] = Call({
      target: Constants.Arc.POOL_MANAGER,
      value: 0,
      data: abi.encodeCall(IPoolManager.setProtocolFeeController, (ArcStandIns.V4_FEE_ADAPTER))
    });
  }

  function _assertCallsEq(Call[] memory actual, Call[] memory expected) internal pure {
    assertEq(actual.length, expected.length, "calls.length");
    for (uint256 i; i < actual.length; i++) {
      assertEq(actual[i].target, expected[i].target, "call.target");
      assertEq(actual[i].value, expected[i].value, "call.value");
      assertEq(actual[i].data, expected[i].data, "call.data");
    }
  }
}
