// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Vm} from "forge-std/Vm.sol";
import {Currency} from "v4-core/types/Currency.sol";

import {HookFamilyAssignment, PairClassFeeAssignment} from "../../src/interfaces/IV4FeePolicy.sol";
import {FeeSchedule} from "./FeeSchedule.sol";

/// @dev Foundry's cheatcode handle. forge-std only exposes it as a member of the contracts a
/// script inherits, so a library declares its own.
Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

/// @dev One `pairClassAssignments` entry as written in the file, before `encode` turns it into
/// the `PairClassFeeAssignment` the policy takes.
struct PairClassInput {
  address token0;
  address token1;
  uint8 familyId;
  uint24 feePips;
}

/// @dev Per-chain `V4FeePolicy` assignments, read from a proposal's JSON file so that a change to
/// a list is a file edit rather than a Solidity edit.
///
/// The file is keyed by EIP-155 chain id, then by the policy setter each array feeds:
///
///   {
///     "<chainId>": {
///       "hookFamilyAssignments": [{"hook": "0x…", "familyId": 11}],
///       "pairClassAssignments": [
///         {"token0": "0x…", "token1": "0x…", "familyId": 11, "feePips": 300}
///       ]
///     }
///   }
///
/// Callers pass `block.chainid`, so a script reads the chain it is running on and no other. Each
/// entry mirrors the struct its setter takes, `HookFamilyAssignment` or `PairClassFeeAssignment`,
/// with two differences that keep the file readable: tokens may appear in either order, and the
/// fee is the protocol fee the pair's pools should charge in pips, not the value the policy
/// stores. `encode` applies both conversions.
///
/// Fields match by name, so their order inside an entry does not matter and extra fields such as
/// a symbol or a note are ignored. A chain id or array that is absent reverts naming the file and
/// key, so a typo cannot read as an empty list. A malformed address, a family id above 255, or a
/// fee that does not encode exactly reverts too.
library V4FeePolicyAssignments {
  string constant HOOK_FAMILY_ASSIGNMENTS = "hookFamilyAssignments";
  string constant PAIR_CLASS_ASSIGNMENTS = "pairClassAssignments";

  string constant HOOK_FAMILY_TYPE = "HookFamilyAssignment(address hook,uint8 familyId)";
  string constant PAIR_CLASS_TYPE =
    "PairClassAssignment(address token0,address token1,uint8 familyId,uint24 feePips)";

  /// @dev This chain's `hookFamilyAssignments`, as `batchSetHookFamily` takes them.
  function hookFamilies(string memory path, uint256 chainId)
    internal
    view
    returns (HookFamilyAssignment[] memory)
  {
    return parseHookFamilies(vm.readFile(path), chainId, path);
  }

  /// @dev This chain's `pairClassAssignments`, encoded as `batchSetPairClassFee` takes them.
  function pairClassFees(string memory path, uint256 chainId)
    internal
    view
    returns (PairClassFeeAssignment[] memory)
  {
    return parsePairClassFees(vm.readFile(path), chainId, path);
  }

  /// @dev `hookFamilies` on a JSON string. `source` names the file in revert messages.
  function parseHookFamilies(string memory json, uint256 chainId, string memory source)
    internal
    view
    returns (HookFamilyAssignment[] memory)
  {
    return abi.decode(
      _array(json, chainId, HOOK_FAMILY_ASSIGNMENTS, HOOK_FAMILY_TYPE, source),
      (HookFamilyAssignment[])
    );
  }

  /// @dev `pairClassFees` on a JSON string. `source` names the file in revert messages.
  function parsePairClassFees(string memory json, uint256 chainId, string memory source)
    internal
    view
    returns (PairClassFeeAssignment[] memory assignments)
  {
    PairClassInput[] memory inputs = abi.decode(
      _array(json, chainId, PAIR_CLASS_ASSIGNMENTS, PAIR_CLASS_TYPE, source), (PairClassInput[])
    );
    assignments = new PairClassFeeAssignment[](inputs.length);
    for (uint256 i; i < inputs.length; i++) {
      assignments[i] = encode(inputs[i]);
    }
  }

  /// @dev Encodes one entry as `V4FeePolicy` stores it.
  ///
  /// - Tokens are sorted ascending, the order `batchSetPairClassFee` requires. Identical tokens
  ///   revert here rather than in the policy.
  /// - `feePips` becomes the stored value through `FeeSchedule.aggHookFeeValue`: divided by the
  ///   aggregator hook multiplier and packed into both swap directions. That multiplier is a
  ///   property of the aggregator family, the only family with a pair-class fee today, so any
  ///   other `familyId` reverts rather than being encoded with a multiplier that is not its own.
  function encode(PairClassInput memory input)
    internal
    pure
    returns (PairClassFeeAssignment memory)
  {
    require(input.token0 != input.token1, "V4FeePolicyAssignments: identical tokens");
    require(
      input.familyId == FeeSchedule.AGG_HOOK_FAMILY_ID,
      "V4FeePolicyAssignments: no pair-class encoding for family"
    );
    (address token0, address token1) = FeeSchedule.sort(input.token0, input.token1);
    return PairClassFeeAssignment({
      currency0: Currency.wrap(token0),
      currency1: Currency.wrap(token1),
      familyId: input.familyId,
      feeValue: FeeSchedule.aggHookFeeValue(input.feePips)
    });
  }

  /// @dev ABI-encodes the array under `<chainId>.<key>`, decoded by field name against
  /// `typeDescription`.
  function _array(
    string memory json,
    uint256 chainId,
    string memory key,
    string memory typeDescription,
    string memory source
  ) private view returns (bytes memory) {
    string memory chainKey = string.concat(".", vm.toString(chainId));
    require(
      vm.keyExistsJson(json, chainKey),
      string.concat(source, ": no entry for chain ", vm.toString(chainId))
    );
    string memory arrayKey = string.concat(chainKey, ".", key);
    require(vm.keyExistsJson(json, arrayKey), string.concat(source, ": missing ", arrayKey));
    return vm.parseJsonTypeArray(json, arrayKey, typeDescription);
  }
}
