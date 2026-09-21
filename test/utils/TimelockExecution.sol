// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Vm} from "forge-std/Vm.sol";
import {Call} from "govkit/types/Call.sol";

/// @dev Executes `calls` as the Timelock, the way the Governor does after the vote, and reverts
/// with the first failing call's revert data.
function executeAsTimelock(Vm vm, address timelock, Call[] memory calls) {
  vm.startPrank(timelock);
  for (uint256 i; i < calls.length; i++) {
    (bool success, bytes memory returndata) =
      calls[i].target.call{value: calls[i].value}(calls[i].data);
    require(success, string(returndata));
  }
  vm.stopPrank();
}
