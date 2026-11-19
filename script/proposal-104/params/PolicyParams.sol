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

/// @dev One `currencyIds` entry as the file writes it. The ID is a string such as "USD", which
///      `loadPolicyParams` converts to `bytes32`.
struct CurrencyIdEntry {
  address currency;
  string id;
}

/// @dev One entry of a hook list as the file writes it.
struct HookEntry {
  address hook;
}

string constant CURRENCY_ID_TYPE = "CurrencyIdEntry(address currency,string id)";
string constant HOOK_TYPE = "HookEntry(address hook)";

/// @notice Reads the parameters of `chainId` from the JSON file at `path`.
/// @dev The file is keyed by EIP-155 chain id:
///
///   {
///     "<chainId>": {
///       "volatilePairFeePips": 1000,
///       "stablePairFeePips": 300,
///       "currencyIds": [{"currency": "0x…", "id": "USD", "symbol": "USDC"}],
///       "aggregatorHooks": [{"hook": "0x…", "name": "…"}],
///       "stablePairHooks": [],
///       "volatilePairHooks": [],
///       "staticCurveHooks": []
///     }
///   }
///
/// Entries match by field name, so extra fields such as `symbol` or `name` document an entry
/// without changing it. Reverts if the chain or any key is missing, or if an ID is empty or longer
/// than 32 bytes.
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

  params.volatilePairFeePips =
    uint24(vm.parseJsonUint(json, _key(json, chainKey, "volatilePairFeePips", path)));
  params.stablePairFeePips =
    uint24(vm.parseJsonUint(json, _key(json, chainKey, "stablePairFeePips", path)));

  CurrencyIdEntry[] memory entries = abi.decode(
    vm.parseJsonTypeArray(json, _key(json, chainKey, "currencyIds", path), CURRENCY_ID_TYPE),
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

  params.aggregatorHooks = _hooks(json, chainKey, "aggregatorHooks", path);
  params.stablePairHooks = _hooks(json, chainKey, "stablePairHooks", path);
  params.volatilePairHooks = _hooks(json, chainKey, "volatilePairHooks", path);
  params.staticCurveHooks = _hooks(json, chainKey, "staticCurveHooks", path);
}

/// @dev Returns the hook addresses under `<chainKey>.<name>`.
function _hooks(string memory json, string memory chainKey, string memory name, string memory path)
  view
  returns (address[] memory hooks)
{
  HookEntry[] memory entries = abi.decode(
    vm.parseJsonTypeArray(json, _key(json, chainKey, name, path), HOOK_TYPE), (HookEntry[])
  );
  hooks = new address[](entries.length);
  for (uint256 i; i < entries.length; i++) {
    hooks[i] = entries[i].hook;
  }
}

/// @dev Returns the key `<chainKey>.<name>`. Reverts if the file does not have it, so a misspelled
///      key cannot read as an empty list.
function _key(string memory json, string memory chainKey, string memory name, string memory path)
  view
  returns (string memory key)
{
  key = string.concat(chainKey, ".", name);
  require(vm.keyExistsJson(json, key), string.concat(path, ": missing ", key));
}
