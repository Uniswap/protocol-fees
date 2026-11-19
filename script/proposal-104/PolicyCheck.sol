// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {V4FeePolicy} from "../../src/feeAdapters/V4FeePolicy.sol";
import {IV4ProtocolFeeRuleset} from "../../src/interfaces/IV4FeePolicy.sol";
import {FeeBucket} from "../../src/interfaces/IV4StaticCurveRuleset.sol";
import {V4StaticCurveRuleset} from "../../src/feeAdapters/rulesets/V4StaticCurveRuleset.sol";
import {V4AggregatorHookRuleset} from "../../src/feeAdapters/rulesets/V4AggregatorHookRuleset.sol";
import {
  AGGREGATOR_HOOK_RULESET_KEY,
  IV4AggregatorHookRuleset
} from "../../src/interfaces/IV4AggregatorHookRuleset.sol";

import {hooklessFeeBuckets} from "./params/Constants.sol";
import {PolicyParams} from "./params/PolicyParams.sol";

/// @notice The contracts that the proposal 104 prerequisite script deploys on one chain.
struct PolicyDeployment {
  V4FeePolicy policy;
  V4StaticCurveRuleset staticCurveRuleset;
  V4AggregatorHookRuleset aggregatorHookRuleset;
  IV4ProtocolFeeRuleset stablePairHookRuleset;
  IV4ProtocolFeeRuleset volatilePairHookRuleset;
}

/// @notice Asserts that `deployment` is the policy and rulesets that `params` describe, handed to
///         `governanceExecutor`.
/// @dev The prerequisite scripts run it on their own deployment, and the preflights run it on the
///      recorded deployment. It reads getters and does not compare code. `V4FeePolicy.rulesets` and
///      `V4AggregatorHookRuleset.id` are mappings, so it cannot detect an entry that `params` does
///      not list.
function checkNewPolicy(
  PolicyDeployment memory deployment,
  PolicyParams memory params,
  address governanceExecutor
) view {
  V4FeePolicy policy = deployment.policy;
  require(address(policy).code.length != 0, "policy.code");

  // Assert the handoff, and that pools no ruleset applies to pay no fee.
  require(policy.owner() == governanceExecutor, "policy.owner");
  require(policy.feeSetter() == governanceExecutor, "policy.feeSetter");
  require(policy.defaultFee() == 0, "policy.defaultFee");

  // Assert hookless pools pay the hookless fee curve, and hooked static-fee pools get no ruleset.
  _requireRuleset(policy, address(0), address(deployment.staticCurveRuleset), "hookless");
  _requireRuleset(policy, policy.NATIVE_MATH_POOL_SENTINEL(), address(0), "nativeMath");
  _checkFeeBuckets(deployment.staticCurveRuleset);

  // Assert the aggregator hook ruleset's fees and currency IDs, and that the policy has it at the
  // key that aggregator hooks forward to.
  V4AggregatorHookRuleset aggregator = deployment.aggregatorHookRuleset;
  require(aggregator.VOLATILE_PAIR_FEE() == params.volatilePairFeePips, "aggregator.volatileFee");
  require(aggregator.STABLE_PAIR_FEE() == params.stablePairFeePips, "aggregator.stableFee");
  for (uint256 i; i < params.currencyIds.length; i++) {
    IV4AggregatorHookRuleset.CurrencyId memory entry = params.currencyIds[i];
    require(aggregator.id(entry.currency) == entry.id, "aggregator.id");
  }
  _requireRuleset(policy, AGGREGATOR_HOOK_RULESET_KEY, address(aggregator), "aggregatorKey");

  // Assert each hook's ruleset.
  _requireRulesets(policy, params.aggregatorHooks, address(aggregator), "aggregatorHook");
  _requireRulesets(
    policy, params.stablePairHooks, address(deployment.stablePairHookRuleset), "stablePairHook"
  );
  _requireRulesets(
    policy,
    params.volatilePairHooks,
    address(deployment.volatilePairHookRuleset),
    "volatilePairHook"
  );
  _requireRulesets(
    policy, params.staticCurveHooks, address(deployment.staticCurveRuleset), "staticCurveHook"
  );
}

/// @dev Asserts the ruleset's buckets equal `hooklessFeeBuckets`.
function _checkFeeBuckets(V4StaticCurveRuleset ruleset) view {
  FeeBucket[] memory expected = hooklessFeeBuckets();
  require(ruleset.feeBucketsLength() == expected.length, "staticCurve.length");
  for (uint256 i; i < expected.length; i++) {
    (uint24 lpFeeFloor, uint24 alphaPips, uint32 betaPips) = ruleset.feeBucket(i);
    require(lpFeeFloor == expected[i].lpFeeFloor, "staticCurve.lpFeeFloor");
    require(alphaPips == expected[i].alphaPips, "staticCurve.alphaPips");
    require(betaPips == expected[i].betaPips, "staticCurve.betaPips");
  }
}

/// @dev Asserts that each of `hooks` has `ruleset` on `policy`.
function _requireRulesets(
  V4FeePolicy policy,
  address[] memory hooks,
  address ruleset,
  string memory label
) view {
  for (uint256 i; i < hooks.length; i++) {
    _requireRuleset(policy, hooks[i], ruleset, label);
  }
}

/// @dev Asserts that `hook` has `ruleset` on `policy`.
function _requireRuleset(V4FeePolicy policy, address hook, address ruleset, string memory label)
  view {
  require(address(policy.rulesets(hook)) == ruleset, string.concat("policy.rulesets.", label));
}
