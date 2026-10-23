// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Recorder} from "govkit/forge/Recorder.sol";
import {vm} from "govkit/forge/Constants.sol";

import "../../script/proposal-7/params/Constants.sol" as Constants;

/// @dev Stand-ins for what the prerequisite script records on Arc, for tests that need
/// `buildProposal` to read a record without an Arc fork. The values only have to be non-zero and
/// distinct.
library ArcStandIns {
  address internal constant NTT_MANAGER = address(0xA1);
  address internal constant WORMHOLE_TRANSCEIVER = address(0xA2);
  address internal constant TOKEN_JAR = address(0xA3);
  address internal constant V3_OPEN_FEE_ADAPTER = address(0xA4);
  address internal constant V4_FEE_ADAPTER = address(0xA5);

  /// @dev Writes the stand-ins under the keys `buildProposal` reads, to the record named
  /// `recordName`.
  function writeRecord(Recorder storage recorder, string memory recordName) internal {
    uint256 chainId = Constants.Arc.CHAIN_ID;

    // Remove any record an earlier run left, so nothing carries over. Callers pick a name unique
    // to their test contract, gitignored as `.records/*Test.json`, so parallel test contracts
    // never write the same file.
    string memory recordPath = string.concat(".records/", recordName, ".json");
    if (vm.exists(recordPath)) vm.removeFile(recordPath);

    recorder.initialize({scriptName: recordName});
    recorder.write(chainId, Constants.Records.NTT_MANAGER, NTT_MANAGER);
    recorder.write(chainId, Constants.Records.WORMHOLE_TRANSCEIVER, WORMHOLE_TRANSCEIVER);
    recorder.write(chainId, Constants.Records.TOKEN_JAR, TOKEN_JAR);
    recorder.write(chainId, Constants.Records.V3_OPEN_FEE_ADAPTER, V3_OPEN_FEE_ADAPTER);
    recorder.write(chainId, Constants.Records.V4_FEE_ADAPTER, V4_FEE_ADAPTER);
  }
}
