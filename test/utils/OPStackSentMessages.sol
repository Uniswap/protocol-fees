// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Vm} from "forge-std/Vm.sol";
import {
  ICrossDomainMessenger
} from "@eth-optimism-bedrock/interfaces/universal/ICrossDomainMessenger.sol";

/// @dev Returns how many `SentMessage` events `messenger`, an OP Stack L1CrossDomainMessenger,
/// emitted in `logs` with `target` as the message's target.
function countOPStackSentMessages(Vm.Log[] memory logs, address messenger, address target)
  pure
  returns (uint256 sent)
{
  for (uint256 i; i < logs.length; i++) {
    if (logs[i].emitter != messenger) continue;
    if (logs[i].topics[0] != ICrossDomainMessenger.SentMessage.selector) continue;
    // An indexed address is left-padded to the 32-byte topic.
    if (logs[i].topics[1] != bytes32(uint256(uint160(target)))) continue;
    sent++;
  }
}
