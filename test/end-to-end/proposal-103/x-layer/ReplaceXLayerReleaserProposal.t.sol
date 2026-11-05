// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {Call} from "govkit/types/Call.sol";
import {ITokenJar} from "govkit/interfaces/ITokenJar.sol";
import {
  L1CrossDomainMessengerDecoder
} from "govkit/bridges/decoders/L1CrossDomainMessengerDecoder.sol";

import {
  buildReplaceReleaserCall
} from "../../../../script/proposal-103/x-layer/ReplaceXLayerReleaser.s.sol";
import {XLayerStandIns} from "../../../utils/XLayerStandIns.sol";

/// @dev Record file these tests write, gitignored as `.records/*Test.json`.
string constant RECORD_NAME = "ReplaceXLayerReleaserProposalTest";

/// @dev Unit tests for the proposal's encoding.
contract ReplaceXLayerReleaserProposalTest is Test {
  Uniswap internal uniswap;
  Recorder internal recorder;

  function setUp() public {
    uniswap.loadLatest();
    XLayerStandIns.writeRecord(recorder, RECORD_NAME);
  }

  /// @dev Asserts the X Layer action is one message through X Layer's L1CrossDomainMessenger to the
  ///      CrossChainAccount, carrying exactly `TokenJar.setReleaser` with the recorded releaser.
  function test_buildReplaceReleaserCall() public view {
    Call memory call = buildReplaceReleaserCall(uniswap, recorder);

    assertEq(call.value, 0, "call.value");

    (
      address l1CrossDomainMessenger,
      address crossChainAccount,
      uint32 gasLimit,
      Call memory remoteCall
    ) = L1CrossDomainMessengerDecoder.decode(call);

    // Assert the envelope: X Layer's messenger, X Layer's CrossChainAccount, the default gas limit.
    assertEq(l1CrossDomainMessenger, uniswap.ethereum.bridge.xLayer, "l1CrossDomainMessenger");
    assertEq(crossChainAccount, uniswap.xLayer.crossChainAccount, "crossChainAccount");
    assertEq(gasLimit, 200_000, "gasLimit");

    // Assert the remote call sets the TokenJar's releaser to the new releaser.
    assertEq(remoteCall.target, uniswap.xLayer.tokenJar, "remoteCall.target");
    assertEq(remoteCall.value, 0, "remoteCall.value");
    assertEq(
      remoteCall.data,
      abi.encodeCall(ITokenJar.setReleaser, (XLayerStandIns.RELEASER)),
      "remoteCall.data"
    );
  }
}
