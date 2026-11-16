// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Recorder} from "govkit/forge/Recorder.sol";
import {vm} from "govkit/forge/Constants.sol";
import {ChainId} from "govkit/constants/ChainId.sol";

import {Records} from "../../script/proposal-103/x-layer/Constants.sol";

/// @dev Stand-in for what the proposal 103 prerequisite script records on X Layer, for tests that
/// need the proposal builders to read a record without an X Layer fork. The value only has to be
/// non-zero.
library XLayerStandIns {
  address internal constant RELEASER = address(0xA1);

  /// @dev Writes the stand-in under the key the proposal builders read, to the record named
  /// `recordName`, and leaves `recorder` initialized on it.
  function writeRecord(Recorder storage recorder, string memory recordName) internal {
    // Remove any record an earlier run left, so nothing carries over. Callers pick a name unique
    // to their test contract, gitignored as `.records/*Test.json`, so parallel test contracts
    // never write the same file.
    string memory recordPath = string.concat(".records/", recordName, ".json");
    if (vm.exists(recordPath)) vm.removeFile(recordPath);

    recorder.initialize({scriptName: recordName});
    recorder.write(ChainId.XLayer, Records.RELEASER, RELEASER);
  }
}
