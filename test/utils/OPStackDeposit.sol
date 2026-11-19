// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Vm} from "forge-std/Vm.sol";
import {Call, LibCall} from "govkit/types/Call.sol";
import {IOptimismPortal2} from "govkit/interfaces/bridges/IOptimismPortal2.sol";
import {IL1CrossDomainMessenger} from "govkit/interfaces/bridges/IL1CrossDomainMessenger.sol";
import {Predeploys} from "@eth-optimism-bedrock/src/libraries/Predeploys.sol";
import {AddressAliasHelper} from "@eth-optimism-bedrock/src/vendor/AddressAliasHelper.sol";

import {executeAsTimelock} from "./TimelockExecution.sol";

/// @dev The deposit transaction an OP Stack chain runs for one message from its
///      L1CrossDomainMessenger.
struct OPStackDeposit {
  /// @dev The L1CrossDomainMessenger's aliased address, the deposit's sender on the chain.
  address from;
  /// @dev The L2CrossDomainMessenger.
  address to;
  uint256 value;
  uint64 gasLimit;
  /// @dev The calldata of `relayMessage` on the L2CrossDomainMessenger.
  bytes data;
}

/// @dev Returns the one deposit in `logs` that `portal` emitted for a message from `l1Messenger`
///      to the L2CrossDomainMessenger. Reverts unless there is exactly one.
/// @dev Proposal 103's X Layer fork test decodes deposits the same way.
function opStackDeposit(Vm.Log[] memory logs, address portal, address l1Messenger)
  pure
  returns (OPStackDeposit memory deposit)
{
  // event TransactionDeposited(
  //    address indexed from,
  //    address indexed to,
  //    uint256 indexed version,
  //    bytes opaqueData
  // );
  //
  // The portal names the L1 messenger by its aliased address, which is the deposit's sender on the
  // chain.
  deposit.from = AddressAliasHelper.applyL1ToL2Alias(l1Messenger);
  deposit.to = Predeploys.L2_CROSS_DOMAIN_MESSENGER;

  uint256 found;
  for (uint256 i; i < logs.length; i++) {
    if (logs[i].emitter != portal) continue;
    if (logs[i].topics[0] != IOptimismPortal2.TransactionDeposited.selector) continue;
    // An indexed address is left-padded to the 32-byte topic.
    if (logs[i].topics[1] != bytes32(uint256(uint160(deposit.from)))) continue;
    if (logs[i].topics[2] != bytes32(uint256(uint160(deposit.to)))) continue;
    // Require a version 0 deposit, the `opaqueData` layout decoded below.
    require(uint256(logs[i].topics[3]) == 0, "TransactionDeposited.version");
    (deposit.value, deposit.gasLimit, deposit.data) =
      _decodeOpaqueData(abi.decode(logs[i].data, (bytes)));
    found++;
  }
  require(found == 1, "TransactionDeposited.count");
}

/// @dev Returns the gas the deposit's call gets on the chain: its gas limit less the intrinsic
///      gas of a transaction carrying its calldata, which is 21,000 plus 4 per zero byte and 16 per
///      non-zero byte (Ethereum Yellow Paper Appendix G, EIP-2028). Assumes the chain charges
///      deposit transactions intrinsic gas like any other transaction; if it does not, the call
///      gets more gas than this, so the replay errs strict.
function opStackDepositCallGas(OPStackDeposit memory deposit) pure returns (uint256) {
  uint256 intrinsic = 21_000;
  for (uint256 i; i < deposit.data.length; i++) {
    intrinsic += deposit.data[i] == 0 ? 4 : 16;
  }
  return deposit.gasLimit - intrinsic;
}

/// @dev Decodes a version 0 deposit's `opaqueData`: `mint` (32 bytes), `value` (32 bytes),
///      `gasLimit` (8 bytes), `isCreation` (1 byte), then `data`.
/// `OptimismPortal2.depositTransaction` packs it as `abi.encodePacked(msg.value, _value, _gasLimit,
/// _isCreation, _data)`, and the
///      OP Stack node reads it in `unmarshalDepositVersion0`.
function _decodeOpaqueData(bytes memory opaqueData)
  pure
  returns (uint256 value, uint64 gasLimit, bytes memory data)
{
  assembly ("memory-safe") {
    value := mload(add(opaqueData, 64))
    gasLimit := shr(192, mload(add(opaqueData, 96)))
  }
  data = new bytes(opaqueData.length - 73);
  for (uint256 i; i < data.length; i++) {
    data[i] = opaqueData[73 + i];
  }
}

/// @dev Executes `action` as the Timelock on `mainnetFork`, then runs the one deposit transaction
///      it creates through `l1Messenger`'s portal on `remoteFork`, as the chain does once it reads
///      the deposit from Ethereum. Reverts if the deposit transaction reverts. If the message's gas
///      limit is too low, the L2CrossDomainMessenger records the message as failed instead of
///      reverting, so callers assert the message's effect afterwards. Leaves `remoteFork`
///      selected.
function relayOPStackMessage(
  Vm vm,
  address timelock,
  Call memory action,
  address l1Messenger,
  uint256 mainnetFork,
  uint256 remoteFork
) {
  vm.selectFork(mainnetFork);
  address portal = IL1CrossDomainMessenger(l1Messenger).PORTAL();
  vm.recordLogs();
  executeAsTimelock(vm, timelock, LibCall.newCalls([action]));
  OPStackDeposit memory deposit = opStackDeposit(vm.getRecordedLogs(), portal, l1Messenger);

  vm.selectFork(remoteFork);
  vm.prank(deposit.from);
  (bool success,) =
    deposit.to.call{value: deposit.value, gas: opStackDepositCallGas(deposit)}(deposit.data);
  require(success, "deposit reverted");
}
