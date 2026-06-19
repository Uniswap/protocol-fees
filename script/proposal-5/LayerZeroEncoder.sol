// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Call, LibCall} from "lib/govkit/src/types/Call.sol";
import {IOmnichainProposalSender} from "./Interfaces.sol";

/// @title Layer Zero Encoder
/// @dev We're writing this here & not in the govkit repository because this is the only time we'll
///      using the layer zero encoding system.
library LayerZeroEncoder {
  /// @dev Encodes an OmnichainProposalSender call.
  /// @param omnichainProposalSender Uniswap's OmnichainProposalSender on Ethereum.
  /// @param layerZeroChainId Layer Zero's chain identifier.
  /// @param remoteCalls Call array to be run from the OmnichainGovernanceExecutor on the remote
  /// chain. @return Proposal-ready call.
  function encode(
    address omnichainProposalSender,
    uint16 layerZeroChainId,
    Call[] memory remoteCalls
  ) internal pure returns (Call memory) {
    (address[] memory targets, uint256[] memory values, bytes[] memory datas) =
      LibCall.decompose(remoteCalls);

    // govkit always sets signatures as empty strings
    string[] memory signatures = new string[](targets.length);

    return Call({
      target: omnichainProposalSender,
      value: 0,
      data: abi.encodeCall(
        IOmnichainProposalSender.execute,
        (layerZeroChainId, abi.encode(targets, values, signatures, datas), new bytes(0))
      )
    });
  }
}
