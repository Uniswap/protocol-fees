// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {vm} from "govkit/forge/Constants.sol";

import {IV4AggregatorHookRuleset} from "../../../src/interfaces/IV4AggregatorHookRuleset.sol";

/// @notice One chain's parameters for `V4FeePolicy` and its rulesets.
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

/// @dev One `ids` entry as the file writes it. The ID is a string such as "USD", which
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

/// @notice Reads the parameters of `chainId` from the JSON file at `path`.
/// @dev The file is keyed by EIP-155 chain id, then by the ruleset each object configures. Each
///      ruleset's `hooks` holds named groups of the hooks it is assigned; the loader joins every
///      group, so the group names only document why each hook is there.
///
///   {
///     "<chainId>": {
///       "V4AggregatorHookRuleset": {
///         "volatilePairFee": 1000,
///         "stablePairFee": 300,
///         "ids": [{"currency": "0x…", "id": "USD", "symbol": "USDC"}],
///         "hooks": {"labs": [{"hook": "0x…"}], "thirdParty": []}
///       },
///       "V4StablePairHookRuleset": {"hooks": {"labs": []}},
///       "V4VolatilePairHookRuleset": {"hooks": {"labs": []}},
///       "V4StaticCurveRuleset": {"hooks": {"v1NativeMathFamily": [], "liquidityLauncher": []}}
///     }
///   }
///
/// Entries match by field name, so extra fields such as `symbol` or `name` document an entry
/// without changing it, and keys other than the four rulesets are ignored. Reverts if the chain,
/// a ruleset, a fee, `ids` or `hooks` is missing, or if an ID is empty or longer than 32 bytes.
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
  string memory aggregator = _key(json, chainKey, AGGREGATOR, path);

  params.volatilePairFeePips =
    uint24(vm.parseJsonUint(json, _key(json, aggregator, "volatilePairFee", path)));
  params.stablePairFeePips =
    uint24(vm.parseJsonUint(json, _key(json, aggregator, "stablePairFee", path)));

  CurrencyIdEntry[] memory entries = abi.decode(
    vm.parseJsonTypeArray(json, _key(json, aggregator, "ids", path), CURRENCY_ID_TYPE),
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
  params.stablePairHooks = _hooks(json, _key(json, chainKey, STABLE_PAIR, path), path);
  params.volatilePairHooks = _hooks(json, _key(json, chainKey, VOLATILE_PAIR, path), path);
  params.staticCurveHooks = _hooks(json, _key(json, chainKey, STATIC_CURVE, path), path);
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
