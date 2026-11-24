// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {vm} from "govkit/forge/Constants.sol";

import {IV4AggregatorHookRuleset} from "../../../src/interfaces/IV4AggregatorHookRuleset.sol";

// -------------------------------------------------------------------------------------------------
// The parameter file
//
// The file is keyed by EIP-155 chain id and ruleset:
//
//   {
//     "<chainId>": {
//       "V4AggregatorHookRuleset": {
//         "volatilePairFee": 1000,
//         "stablePairFee": 300,
//         "currencyIds": [{"currency": "0x…", "id": "USD", "symbol": "USDC"}],
//         "hooks": {"labs": [{"hook": "0x…"}], "thirdParty": []}
//       },
//       "V4StablePairHookRuleset": {"hooks": {"labs": []}},
//       "V4VolatilePairHookRuleset": {"hooks": {"labs": []}},
//       "V4StaticCurveRuleset": {"hooks": {"v1NativeMathFamily": [], "liquidityLauncher": []}},
//       "excludedAggregatorFlagHooks": [{"hook": "0x…", "reason": "…"}]
//     }
//   }
//
// Each ruleset's `hooks` lists the hooks that will be assigned to it, grouped by category for
// documentation purposes.
//
// - `V4AggregatorHookRuleset.labs`: Uniswap Labs hooks whose `protocolFeeFlags()` returns 2048.
// - `V4AggregatorHookRuleset.thirdParty`: aggregator hooks from other teams.
// - `V4StablePairHookRuleset.labs` and `V4VolatilePairHookRuleset.labs`: the hook proxies whose
//   `feeConfig` returns the StablePairHook or VolatilePairHook configuration.
// - `V4StaticCurveRuleset.v1NativeMathFamily`: the hooks that the v1 policy currently assigns to
//    its native-math family, 255.
// - `V4StaticCurveRuleset.liquidityLauncher`: Uniswap liquidity-launcher hooks that the v1 policy
//    does not currently assign.
//
// `excludedAggregatorFlagHooks` lists hooks with the aggregator flag that won't be configured by
// these proposals, for documentation purposes only. (The `LitePSMAggregator` hooks are not listed
// at all.)

/// @notice Parameters for `V4FeePolicy` and its rulesets, for a given chain.
struct PolicyParams {
  /// @dev The fee that aggregator hooks charge on pairs that are not stable pairs, in pips per
  ///      direction, after the hook's multiplier.
  uint24 volatilePairFeePips;
  /// @dev The fee that aggregator hooks charge on stable pairs, in pips per direction, after the
  ///      hook's multiplier.
  uint24 stablePairFeePips;
  /// @dev The currencies that have an ID in `V4AggregatorHookRuleset`. Two currencies with the
  ///      same ID form a stable pair.
  IV4AggregatorHookRuleset.CurrencyId[] currencyIds;
  /// @dev Hooks assigned `V4AggregatorHookRuleset`.
  address[] aggregatorHooks;
  /// @dev Hooks assigned `V4StablePairHookRuleset`.
  address[] stablePairHooks;
  /// @dev Hooks assigned `V4VolatilePairHookRuleset`.
  address[] volatilePairHooks;
  /// @dev Hooks assigned `V4StaticCurveRuleset`, so their pools pay the hookless fee.
  address[] staticCurveHooks;
}

/// @dev One `currencyIds` entry as the file writes it. The ID is a string such as "USD", which
///      `loadPolicyParams` converts to `bytes32`.
struct CurrencyIdEntry {
  address currency;
  string id;
}

/// @dev One entry of a hook group as the file writes it.
struct HookEntry {
  address hook;
}

string constant CURRENCY_ID_TYPE = "CurrencyIdEntry(address currency,string id)";
string constant HOOK_TYPE = "HookEntry(address hook)";

string constant AGGREGATOR = "V4AggregatorHookRuleset";
string constant STABLE_PAIR = "V4StablePairHookRuleset";
string constant VOLATILE_PAIR = "V4VolatilePairHookRuleset";
string constant STATIC_CURVE = "V4StaticCurveRuleset";
string constant EXCLUDED = "excludedAggregatorFlagHooks";

/// @notice Reads the parameters of `chainId` from the JSON file at `path`.
/// @dev Joins every hook group under each ruleset. Reverts if the chain, a ruleset, a fee,
/// `currencyIds`, `hooks` or `excludedAggregatorFlagHooks` is missing, if a chain or ruleset object
/// has any other key, if a fee does not fit in `uint24`, or if an ID is empty or longer than
/// 32 bytes.
function loadPolicyParams(string memory path, uint256 chainId)
  view
  returns (PolicyParams memory params)
{
  string memory json = vm.readFile(path);
  string memory chainKey = string.concat(".", vm.toString(chainId));
  require(
    vm.keyExistsJson(json, chainKey),
    string.concat(path, ": no entry for chain ", vm.toString(chainId))
  );
  // Require the four rulesets and the exclusion list, and no other key.
  _key(json, chainKey, EXCLUDED, path);
  _requireKeyCount(json, chainKey, 5, path);

  // Require the two fees, `currencyIds` and `hooks`, and no other key.
  string memory aggregator = _key(json, chainKey, AGGREGATOR, path);
  _requireKeyCount(json, aggregator, 4, path);

  params.volatilePairFeePips = _fee(json, _key(json, aggregator, "volatilePairFee", path), path);
  params.stablePairFeePips = _fee(json, _key(json, aggregator, "stablePairFee", path), path);

  CurrencyIdEntry[] memory entries = abi.decode(
    vm.parseJsonTypeArray(json, _key(json, aggregator, "currencyIds", path), CURRENCY_ID_TYPE),
    (CurrencyIdEntry[])
  );
  params.currencyIds = new IV4AggregatorHookRuleset.CurrencyId[](entries.length);
  for (uint256 i; i < entries.length; i++) {
    bytes memory id = bytes(entries[i].id);
    require(id.length != 0 && id.length <= 32, string.concat(path, ": bad id ", entries[i].id));
    params.currencyIds[i] = IV4AggregatorHookRuleset.CurrencyId({
      currency: Currency.wrap(entries[i].currency), id: bytes32(id)
    });
  }

  params.aggregatorHooks = _hooks(json, aggregator, path);
  params.stablePairHooks = _pairOrStaticHooks(json, chainKey, STABLE_PAIR, path);
  params.volatilePairHooks = _pairOrStaticHooks(json, chainKey, VOLATILE_PAIR, path);
  params.staticCurveHooks = _pairOrStaticHooks(json, chainKey, STATIC_CURVE, path);
}

/// @dev Returns the hooks of the ruleset object `<chainKey>.<ruleset>`, which may hold only
///      `hooks`.
function _pairOrStaticHooks(
  string memory json,
  string memory chainKey,
  string memory ruleset,
  string memory path
) view returns (address[] memory) {
  string memory rulesetKey = _key(json, chainKey, ruleset, path);
  // Require `hooks` and no other key.
  _requireKeyCount(json, rulesetKey, 1, path);
  return _hooks(json, rulesetKey, path);
}

/// @dev Returns the fee at `key`. Reverts if it does not fit in `uint24`, so a mistyped fee cannot
///      truncate to another fee.
function _fee(string memory json, string memory key, string memory path) pure returns (uint24) {
  uint256 fee = vm.parseJsonUint(json, key);
  require(fee <= type(uint24).max, string.concat(path, ": fee too large at ", key));
  return uint24(fee);
}

/// @dev Reverts if the object at `key` does not have exactly `count` keys. The caller requires
///      each key it reads, so a count that matches leaves no room for a misplaced key.
function _requireKeyCount(string memory json, string memory key, uint256 count, string memory path)
  pure {
  require(
    vm.parseJsonKeys(json, key).length == count, string.concat(path, ": unexpected key in ", key)
  );
}

/// @dev Returns the hook addresses in every group under `<rulesetKey>.hooks`, in the file's order.
function _hooks(string memory json, string memory rulesetKey, string memory path)
  view
  returns (address[] memory hooks)
{
  string memory hooksKey = _key(json, rulesetKey, "hooks", path);
  string[] memory groups = vm.parseJsonKeys(json, hooksKey);

  HookEntry[][] memory entries = new HookEntry[][](groups.length);
  uint256 count;
  for (uint256 i; i < groups.length; i++) {
    entries[i] = abi.decode(
      vm.parseJsonTypeArray(json, string.concat(hooksKey, ".", groups[i]), HOOK_TYPE), (HookEntry[])
    );
    count += entries[i].length;
  }

  hooks = new address[](count);
  uint256 next;
  for (uint256 i; i < entries.length; i++) {
    for (uint256 j; j < entries[i].length; j++) {
      hooks[next++] = entries[i][j].hook;
    }
  }
}

/// @dev Returns the key `<parent>.<name>`. Reverts if the file does not have it, so a misspelled
///      key cannot read as an empty list.
function _key(string memory json, string memory parent, string memory name, string memory path)
  view
  returns (string memory key)
{
  key = string.concat(parent, ".", name);
  require(vm.keyExistsJson(json, key), string.concat(path, ": missing ", key));
}
