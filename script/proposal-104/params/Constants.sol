// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ChainId} from "govkit/constants/ChainId.sol";

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

/// @dev Per-chain policy parameters, read by `loadPolicyParams`. Each chain's entry has one object
///      per ruleset, keyed by the ruleset's contract name, with the hooks it is assigned in named
///      groups:
///
///      - `V4AggregatorHookRuleset`: the constructor's `volatilePairFee`, `stablePairFee` and
///        `ids`, and the aggregator hooks. `labs` holds the Uniswap Labs hooks whose
///        `protocolFeeFlags()` returns 2048, and `thirdParty` holds aggregator hooks from other
///        teams. `ids` gives one ID to each group of currencies that trade at parity: USD,
///        BTC, ETH, GOLD, EUR, JPY, SOL, XRP and LINK. A pair of two currencies with the same ID
///        pays `stablePairFee`.
///      - `V4StablePairHookRuleset` and `V4VolatilePairHookRuleset`: the hook proxies whose
///        `feeConfig` returns the StablePairHook or VolatilePairHook configuration.
///      - `V4StaticCurveRuleset`: `v1NativeMathFamily` holds the hooks the v1 policy assigns to its
///        native-math family, 255. `liquidityLauncher` holds the Uniswap liquidity-launcher hooks
///        that the v1 policy does not assign.
///      - `excludedAggregatorFlagHooks`: hooks with the aggregator flag that get no ruleset, each
///        with its reason. `loadPolicyParams` does not read it. The `LitePSMAggregator` hooks
///        report flag 4096 instead and are in no list, because they pay no fee.
string constant POLICY_PARAMS_JSON = "script/proposal-104/params/v4-fee-policy.json";

/// @dev Keys in the record file, one per deployment.
library Records {
  string constant V4_FEE_POLICY = "V4FeePolicy";
  string constant V4_STATIC_CURVE_RULESET = "V4StaticCurveRuleset";
  string constant V4_AGGREGATOR_HOOK_RULESET = "V4AggregatorHookRuleset";
  string constant V4_STABLE_PAIR_HOOK_RULESET = "V4StablePairHookRuleset";
  string constant V4_VOLATILE_PAIR_HOOK_RULESET = "V4VolatilePairHookRuleset";
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

/// @dev Returns the `V4FeeAdapter` that is the PoolManager's `protocolFeeController` on
///      `chainId`. Proposal 6 deployed the first seven and recorded them in
///      `.records/DeployV4FeeInfra.json`; proposal 7 deployed Arc's and recorded it in
///      `.records/Arc.json`.
function v4FeeAdapter(uint256 chainId) pure returns (address) {
  if (chainId == ChainId.Ethereum) return 0x89A5D5bF00a27D55c02951E49078a5C5771051dB;
  if (chainId == ChainId.Arbitrum) return 0x6b3C04567CC62fc5D6AB8D50f1bc1Dee161eb2Cc;
  if (chainId == ChainId.Base) return 0xc53DD825dedBE7814562528A1A30e8e5BCbB4b55;
  if (chainId == ChainId.Optimism) return 0xd85393784234fB2ee4f077867A8B78E1aD4cE56B;
  if (chainId == ChainId.BNBChain) return 0x66276D2e80784180E4B9b859e4327b9C5646B87c;
  if (chainId == ChainId.Polygon) return 0x59e84309Afa65F084F9c03668583d231afB12cc6;
  if (chainId == ChainId.Robinhood) return 0x6d0009504D129CF5002Dba61D9Ae8575AA79314c;
  if (chainId == Arc.CHAIN_ID) return 0x2f2bd3F43880b9644211f16d861b0672aaB23782;
  revert("no V4FeeAdapter for chain");
}

/// @dev Returns the v1 `V4FeePolicy` that the adapter on `chainId` uses before the proposal.
///      Proposal 6 deployed the first seven and recorded them in `.records/DeployV4FeeInfra.json`;
///      proposal 7 deployed Arc's and recorded it in `.records/Arc.json`.
function replacedV4FeePolicy(uint256 chainId) pure returns (address) {
  if (chainId == ChainId.Ethereum) return 0x1cd822b70a0591420F65E94b9B3A0D0b0fB3a314;
  if (chainId == ChainId.Arbitrum) return 0x8F6a5A19Ff1adc6AA9456d6b201fA4FC7589BD0B;
  if (chainId == ChainId.Base) return 0xf963bdbe8BA2aABBB3190fF2268F3d833393ab71;
  if (chainId == ChainId.Optimism) return 0x13d9D19802660b8167B3c84C1fcDCD0163672eB8;
  if (chainId == ChainId.BNBChain) return 0x020B1Ad79037f02feC357Ec4601fFbe5f7ED6872;
  if (chainId == ChainId.Polygon) return 0x600c29d3Ce95Ce503FAb43753cbcb5Fa87EE6093;
  if (chainId == ChainId.Robinhood) return 0x6ee984309ba26c224f12Bb85D6F7f3C019483DFc;
  if (chainId == Arc.CHAIN_ID) return 0x9671B518dA771c5c73d8115b3800FA7653a72015;
  revert("no replaced V4FeePolicy for chain");
}

/// @dev Polygon's FxChild, which delivers FxRoot messages to the governance-owned
///      `EthereumProxy`.
///      https://polygonscan.com/address/0x8397259c983751DAf40400790063935a11AFa28a
address constant POLYGON_FX_CHILD = 0x8397259c983751DAf40400790063935a11afa28a;
