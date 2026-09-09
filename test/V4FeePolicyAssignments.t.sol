// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {Currency} from "v4-core/types/Currency.sol";

import {PairClassInput, V4FeePolicyAssignments} from "../script/shared/V4FeePolicyAssignments.sol";
import {HookFamilyAssignment, PairClassFeeAssignment} from "../src/interfaces/IV4FeePolicy.sol";

contract V4FeePolicyAssignmentsTest is Test {
  string constant SOURCE = "v4-fee-policy.json";
  uint256 constant CHAIN = 999;
  uint256 constant OTHER_CHAIN = 5042;

  address constant HOOK_A = 0x000000000000000000000000000000000000A000;
  address constant HOOK_B = 0x000000000000000000000000000000000000b000;
  address constant TOKEN_LOW = 0x0000000000000000000000000000000000000001;
  address constant TOKEN_HIGH = 0x0000000000000000000000000000000000000002;

  /// @dev 300 pips / 25 = 12 per direction, packed as 12 << 12 | 12.
  uint24 constant FEE_VALUE_300 = 49_164;

  // ─── Fixtures ───

  function hook(address addr, uint256 familyId) internal pure returns (string memory) {
    return
      string.concat('{"hook": "', vm.toString(addr), '", "familyId": ', vm.toString(familyId), "}");
  }

  function pair(address t0, address t1, uint256 familyId, uint256 feePips)
    internal
    pure
    returns (string memory)
  {
    return string.concat(
      '{"token0": "',
      vm.toString(t0),
      '", "token1": "',
      vm.toString(t1),
      '", "familyId": ',
      vm.toString(familyId),
      ', "feePips": ',
      vm.toString(feePips),
      "}"
    );
  }

  function chain(uint256 chainId, string memory hooks, string memory pairs)
    internal
    pure
    returns (string memory)
  {
    return string.concat(
      '"',
      vm.toString(chainId),
      '": {"hookFamilyAssignments": [',
      hooks,
      '], "pairClassAssignments": [',
      pairs,
      "]}"
    );
  }

  function file(string memory chains) internal pure returns (string memory) {
    return string.concat("{", chains, "}");
  }

  // ─── Parsing ───

  function test_parsesBothArraysForTheChain() public view {
    string memory json = file(chain(CHAIN, hook(HOOK_A, 11), pair(TOKEN_LOW, TOKEN_HIGH, 11, 300)));

    HookFamilyAssignment[] memory hooks =
      V4FeePolicyAssignments.parseHookFamilies(json, CHAIN, SOURCE);
    assertEq(hooks.length, 1);
    assertEq(hooks[0].hook, HOOK_A);
    assertEq(hooks[0].familyId, 11);

    PairClassFeeAssignment[] memory pairs =
      V4FeePolicyAssignments.parsePairClassFees(json, CHAIN, SOURCE);
    assertEq(pairs.length, 1);
    assertEq(Currency.unwrap(pairs[0].currency0), TOKEN_LOW);
    assertEq(Currency.unwrap(pairs[0].currency1), TOKEN_HIGH);
    assertEq(pairs[0].familyId, 11);
    assertEq(pairs[0].feeValue, FEE_VALUE_300);
  }

  function test_emptyArraysParse() public view {
    string memory json = file(chain(CHAIN, "", ""));
    assertEq(V4FeePolicyAssignments.parseHookFamilies(json, CHAIN, SOURCE).length, 0);
    assertEq(V4FeePolicyAssignments.parsePairClassFees(json, CHAIN, SOURCE).length, 0);
  }

  function test_selectsTheChainAskedFor() public view {
    string memory json = file(
      string.concat(
        chain(CHAIN, hook(HOOK_A, 11), ""), ",", chain(OTHER_CHAIN, hook(HOOK_B, 3), "")
      )
    );

    HookFamilyAssignment[] memory hooks =
      V4FeePolicyAssignments.parseHookFamilies(json, CHAIN, SOURCE);
    assertEq(hooks[0].hook, HOOK_A);
    assertEq(hooks[0].familyId, 11);

    hooks = V4FeePolicyAssignments.parseHookFamilies(json, OTHER_CHAIN, SOURCE);
    assertEq(hooks[0].hook, HOOK_B);
    assertEq(hooks[0].familyId, 3);
  }

  function test_matchesFieldsByNameAndIgnoresExtras() public view {
    string memory json = file(
      chain(
        CHAIN,
        string.concat('{"familyId": 3, "note": "reordered", "hook": "', vm.toString(HOOK_B), '"}'),
        string.concat(
          '{"feePips": 300, "symbol": "USDC/USDT", "familyId": 11, "token1": "',
          vm.toString(TOKEN_HIGH),
          '", "token0": "',
          vm.toString(TOKEN_LOW),
          '"}'
        )
      )
    );

    HookFamilyAssignment[] memory hooks =
      V4FeePolicyAssignments.parseHookFamilies(json, CHAIN, SOURCE);
    assertEq(hooks[0].hook, HOOK_B);
    assertEq(hooks[0].familyId, 3);

    PairClassFeeAssignment[] memory pairs =
      V4FeePolicyAssignments.parsePairClassFees(json, CHAIN, SOURCE);
    assertEq(Currency.unwrap(pairs[0].currency0), TOKEN_LOW);
    assertEq(pairs[0].feeValue, FEE_VALUE_300);
  }

  // ─── Missing keys ───

  function test_missingChainReverts() public {
    string memory json = file(chain(OTHER_CHAIN, "", ""));
    vm.expectRevert(bytes("v4-fee-policy.json: no entry for chain 999"));
    this.hookFamilies(json, CHAIN);
  }

  function test_missingArrayReverts() public {
    string memory json =
      string.concat('{"', vm.toString(CHAIN), '": {"hookFamilyAssignments": []}}');
    vm.expectRevert(bytes("v4-fee-policy.json: missing .999.pairClassAssignments"));
    this.pairClassFees(json, CHAIN);
  }

  // ─── Malformed entries ───

  function test_hookFamilyIdAbove255Reverts() public {
    string memory json = file(chain(CHAIN, hook(HOOK_A, 256), ""));
    vm.expectRevert();
    this.hookFamilies(json, CHAIN);
  }

  function test_malformedAddressReverts() public {
    string memory json = file(chain(CHAIN, '{"hook": "0xA000", "familyId": 1}', ""));
    vm.expectRevert();
    this.hookFamilies(json, CHAIN);
  }

  // ─── Pair-class encoding ───

  function test_sortsTokens() public view {
    string memory json = file(chain(CHAIN, "", pair(TOKEN_HIGH, TOKEN_LOW, 11, 300)));
    PairClassFeeAssignment[] memory pairs =
      V4FeePolicyAssignments.parsePairClassFees(json, CHAIN, SOURCE);
    assertEq(Currency.unwrap(pairs[0].currency0), TOKEN_LOW);
    assertEq(Currency.unwrap(pairs[0].currency1), TOKEN_HIGH);
  }

  function test_identicalTokensRevert() public {
    string memory json = file(chain(CHAIN, "", pair(TOKEN_LOW, TOKEN_LOW, 11, 300)));
    vm.expectRevert(bytes("V4FeePolicyAssignments: identical tokens"));
    this.pairClassFees(json, CHAIN);
  }

  function test_nonAggregatorFamilyReverts() public {
    string memory json = file(chain(CHAIN, "", pair(TOKEN_LOW, TOKEN_HIGH, 12, 300)));
    vm.expectRevert(bytes("V4FeePolicyAssignments: no pair-class encoding for family"));
    this.pairClassFees(json, CHAIN);
  }

  function test_feeNotMultipleOf25Reverts() public {
    string memory json = file(chain(CHAIN, "", pair(TOKEN_LOW, TOKEN_HIGH, 11, 310)));
    vm.expectRevert(bytes("FeeSchedule: fee not a multiple of 25 pips"));
    this.pairClassFees(json, CHAIN);
  }

  function test_feeAboveCapReverts() public {
    string memory json = file(chain(CHAIN, "", pair(TOKEN_LOW, TOKEN_HIGH, 11, 25_025)));
    vm.expectRevert(bytes("FeeSchedule: fee above the v4 cap"));
    this.pairClassFees(json, CHAIN);
  }

  function test_encodeMatchesProposal6Values() public pure {
    // Proposal 6 stored encodeFee(300 / 25) for stable-stable pairs and encodeFee(100 / 25) on
    // Base, where encodeFee(fee) = fee << 12 | fee.
    assertEq(encode(300).feeValue, 49_164);
    assertEq(encode(100).feeValue, 16_388);
  }

  function testFuzz_encodeStoresFeeOver25InBothDirections(uint24 perDirection) public pure {
    perDirection = uint24(bound(perDirection, 0, 1000));
    uint24 feeValue = encode(perDirection * 25).feeValue;
    assertEq(feeValue & 0xfff, perDirection, "zero-for-one");
    assertEq(feeValue >> 12, perDirection, "one-for-zero");
  }

  // ─── Helpers ───

  function encode(uint24 feePips) internal pure returns (PairClassFeeAssignment memory) {
    return V4FeePolicyAssignments.encode(
      PairClassInput({token0: TOKEN_LOW, token1: TOKEN_HIGH, familyId: 11, feePips: feePips})
    );
  }

  function hookFamilies(string memory json, uint256 chainId)
    external
    view
    returns (HookFamilyAssignment[] memory)
  {
    return V4FeePolicyAssignments.parseHookFamilies(json, chainId, SOURCE);
  }

  function pairClassFees(string memory json, uint256 chainId)
    external
    view
    returns (PairClassFeeAssignment[] memory)
  {
    return V4FeePolicyAssignments.parsePairClassFees(json, chainId, SOURCE);
  }
}
