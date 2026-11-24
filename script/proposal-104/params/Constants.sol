// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ChainId} from "govkit/constants/ChainId.sol";
import {vm} from "govkit/forge/Constants.sol";
import {Recorder} from "govkit/forge/Recorder.sol";

import {FeeBucket} from "../../../src/interfaces/IV4StaticCurveRuleset.sol";
import {Arc} from "../../proposal-7/params/Constants.sol";

// -------------------------------------------------------------------------------------------------
// Proposal 104 parameters
//
// Proposal 105 deploys the same policy and rulesets on five more chains, so it imports this file
// and overrides only its record name and parameter file.

/// @dev Record file shared by the prerequisite script and the proposal, at
///      `.records/<RECORD_NAME>.json`.
string constant RECORD_NAME = "Proposal104";

/// @dev Per-chain policy parameters, in the format described by `PolicyParams.sol`.
string constant POLICY_PARAMS_JSON = "script/proposal-104/params/v4-fee-policy.json";

/// @dev The eight chains, in the order of the proposal's actions.
function chains() pure returns (uint256[8] memory) {
  return [
    ChainId.Ethereum,
    ChainId.Arbitrum,
    ChainId.Base,
    ChainId.Optimism,
    ChainId.BNBChain,
    ChainId.Polygon,
    ChainId.Robinhood,
    Arc.CHAIN_ID
  ];
}

/// @dev Keys in the record file, one per deployment.
library Records {
  string constant V4_FEE_POLICY = "V4FeePolicy";
  string constant V4_STATIC_CURVE_RULESET = "V4StaticCurveRuleset";
  string constant V4_AGGREGATOR_HOOK_RULESET = "V4AggregatorHookRuleset";
  string constant V4_STABLE_PAIR_HOOK_RULESET = "V4StablePairHookRuleset";
  string constant V4_VOLATILE_PAIR_HOOK_RULESET = "V4VolatilePairHookRuleset";
}

/// @dev Returns the address recorded under `key` for `chainId` in `recorder`'s file. Reverts
///      naming the chain, the key and the file if the file has no such entry, as when the
///      prerequisite script has not run on that chain.
function readRecord(Recorder storage recorder, uint256 chainId, string memory key)
  view
  returns (address)
{
  require(
    recorder.exists(chainId, key),
    string.concat(
      "no ",
      key,
      " recorded for chain ",
      vm.toString(chainId),
      " in ",
      recorder.path(),
      ": run the prerequisite script on that chain"
    )
  );
  return recorder.read(chainId, key);
}

/// @dev The hookless fee curve. These are the buckets proposal 6 set on each v1 `V4FeePolicy`,
///      from `script/shared/FeeSchedule.sol` on `main` at `eacc9c013c`.
function hooklessFeeBuckets() pure returns (FeeBucket[] memory buckets) {
  buckets = new FeeBucket[](8);
  buckets[0] = FeeBucket({lpFeeFloor: 0, alphaPips: 1, betaPips: 0});
  buckets[1] = FeeBucket({lpFeeFloor: 3, alphaPips: 1, betaPips: 263_889});
  buckets[2] = FeeBucket({lpFeeFloor: 75, alphaPips: 20, betaPips: 200_000});
  buckets[3] = FeeBucket({lpFeeFloor: 100, alphaPips: 25, betaPips: 272_728});
  buckets[4] = FeeBucket({lpFeeFloor: 375, alphaPips: 100, betaPips: 200_000});
  buckets[5] = FeeBucket({lpFeeFloor: 500, alphaPips: 125, betaPips: 137_500});
  buckets[6] = FeeBucket({lpFeeFloor: 2500, alphaPips: 400, betaPips: 200_000});
  buckets[7] = FeeBucket({lpFeeFloor: 5500, alphaPips: 1000, betaPips: 0});
}

/// @dev The record file in which proposal 6 recorded the v1 `V4FeeAdapter` and `V4FeePolicy` of
///      every chain but Arc.
string constant V1_RECORD = ".records/DeployV4FeeInfra.json";

/// @dev The record file in which proposal 7 recorded Arc's v1 `V4FeeAdapter` and `V4FeePolicy`.
string constant ARC_RECORD = ".records/Arc.json";

/// @dev Returns the `V4FeeAdapter` that is the PoolManager's `protocolFeeController` on
///      `chainId`, from its v1 record.
function v4FeeAdapter(uint256 chainId) view returns (address) {
  return _v1Deployment(chainId, "V4FeeAdapter");
}

/// @dev Returns the v1 `V4FeePolicy` that the adapter on `chainId` uses before the proposal, from
///      its v1 record.
function replacedV4FeePolicy(uint256 chainId) view returns (address) {
  return _v1Deployment(chainId, "V4FeePolicy");
}

/// @dev Returns the address recorded under `key` for `chainId` in `ARC_RECORD` for Arc, and in
///      `V1_RECORD` for the other chains. Reverts for a chain the proposal does not act on, since
///      `V1_RECORD` also holds Celo's, which no PoolManager uses.
function _v1Deployment(uint256 chainId, string memory key) view returns (address) {
  bool found;
  uint256[8] memory list = chains();
  for (uint256 i; i < list.length; i++) {
    if (list[i] == chainId) found = true;
  }
  require(found, string.concat("no v1 ", key, " for chain"));

  string memory path = chainId == Arc.CHAIN_ID ? ARC_RECORD : V1_RECORD;
  return vm.parseJsonAddress(vm.readFile(path), string.concat(".", vm.toString(chainId), ".", key));
}

/// @dev Polygon's FxChild, which delivers FxRoot messages to the governance-owned
///      `EthereumProxy`.
///      https://polygonscan.com/address/0x8397259c983751DAf40400790063935a11AFa28a
address constant POLYGON_FX_CHILD = 0x8397259c983751DAf40400790063935a11afa28a;
