// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";

import {V4FeePolicy} from "../../../src/feeAdapters/V4FeePolicy.sol";
import {
  IV4ProtocolFeeRuleset,
  ProtocolFeeRulesetAssignment
} from "../../../src/interfaces/IV4FeePolicy.sol";
import {AGGREGATOR_HOOK_RULESET_KEY} from "../../../src/interfaces/IV4AggregatorHookRuleset.sol";
import {V4StaticCurveRuleset} from "../../../src/feeAdapters/rulesets/V4StaticCurveRuleset.sol";
import {
  V4AggregatorHookRuleset
} from "../../../src/feeAdapters/rulesets/V4AggregatorHookRuleset.sol";
import {
  V4StablePairHookRuleset
} from "../../../src/feeAdapters/rulesets/V4StablePairHookRuleset.sol";
import {
  V4VolatilePairHookRuleset
} from "../../../src/feeAdapters/rulesets/V4VolatilePairHookRuleset.sol";

import {
  RECORD_NAME,
  POLICY_PARAMS_JSON,
  Records,
  hooklessFeeBuckets,
  readRecord
} from "../params/Constants.sol";
import {v4Accounts} from "../params/Chains.sol";
import {PolicyParams, loadPolicyParams} from "../params/PolicyParams.sol";
import {PolicyDeployment, checkNewPolicy} from "../PolicyCheck.sol";

/// @dev The number of ruleset assignments per `batchSetProtocolFeeRulesets` call. Each new
///      assignment costs about 26,000 gas, and `forge script` sets a transaction's gas limit 30%
///      above its estimate, so 400 keep the limit under Ethereum's per-transaction gas cap of
///      16,777,216 (EIP-7825).
uint256 constant ASSIGNMENTS_PER_TRANSACTION = 400;

/// @title DeployV4FeePolicy
/// @notice Deploys a `V4FeePolicy` and its four rulesets on one chain, assigns each ruleset to
///         its hooks, hands the policy to the chain's governance executor, and records the
///         addresses in `.records/Proposal104.json`, where the proposal reads them. Anyone can run
///         it; the deployer holds no authority once it finishes.
/// @dev Run it once on each of the eight proposal 104 chains:
///
///      forge script script/proposal-104/prereq/DeployV4FeePolicy.s.sol --rpc-url <chain> \
///        --broadcast
///
///      `run` asserts the result in its own simulation before it records anything. To apply the
///      same assertions to the live chain afterwards, from the record alone:
///
///      forge script script/proposal-104/prereq/DeployV4FeePolicy.s.sol --sig "check()" \
///        --rpc-url <chain>
///
///      Proposal 105 extends this script to also deploy a `V4FeeAdapter`.
contract DeployV4FeePolicy is Script {
  Recorder internal recorder;
  Uniswap internal uniswap;

  PolicyParams internal params;
  address internal governanceExecutor;
  /// @dev The account that sends the broadcast transactions.
  address internal deployer;
  PolicyDeployment internal deployment;

  function run() external {
    _initialize();

    // The recorder writes only after `_check` passes and never during a dry run, so a record here
    // means an earlier `--broadcast` run simulated cleanly. Overwriting it would point the proposal
    // at a different deployment, so to redeploy, clear the record deliberately.
    require(
      !recorder.exists({chainId: block.chainid, deploymentName: Records.V4_FEE_POLICY}),
      "already deployed: clear .records/ to redeploy"
    );

    vm.startBroadcast();
    (, deployer,) = vm.readCallers();
    _deploy();
    vm.stopBroadcast();

    _check();
    _record();
  }

  /// @notice Asserts the recorded deployment on the chain the script runs against.
  /// @dev `run` applies the same assertions to its own simulation before it records anything.
  function check() external {
    _initialize();
    _read();
    _check();
  }

  /// @notice Loads this chain's parameters and governance executor.
  function _initialize() internal {
    uniswap.loadLatest();
    recorder.initialize({scriptName: _recordName()});

    PolicyParams memory loaded = loadPolicyParams(_paramsPath(), block.chainid);
    params.volatilePairFeePips = loaded.volatilePairFeePips;
    params.stablePairFeePips = loaded.stablePairFeePips;
    delete params.currencyIds;
    for (uint256 i; i < loaded.currencyIds.length; i++) {
      params.currencyIds.push(loaded.currencyIds[i]);
    }
    params.aggregatorHooks = loaded.aggregatorHooks;
    params.stablePairHooks = loaded.stablePairHooks;
    params.volatilePairHooks = loaded.volatilePairHooks;
    params.staticCurveHooks = loaded.staticCurveHooks;

    governanceExecutor = v4Accounts(uniswap, block.chainid).governanceExecutor;
  }

  /// @notice Deploys and configures the policy and its rulesets, then hands the policy to the
  ///         governance executor.
  /// @dev Assumes the caller broadcasts.
  function _deploy() internal virtual {
    // ---------------------------------------------------------------------------------------------
    // Transactions 00 to 03
    //
    // Deploy the four rulesets. None has an owner, and the static curve and aggregator rulesets
    // fix their parameters at deployment.
    //
    deployment.staticCurveRuleset = new V4StaticCurveRuleset(hooklessFeeBuckets());
    deployment.aggregatorHookRuleset = new V4AggregatorHookRuleset({
      volatilePairFee: params.volatilePairFeePips,
      stablePairFee: params.stablePairFeePips,
      ids: params.currencyIds
    });
    deployment.stablePairHookRuleset = new V4StablePairHookRuleset();
    deployment.volatilePairHookRuleset = new V4VolatilePairHookRuleset();

    // ---------------------------------------------------------------------------------------------
    // Transaction 04
    //
    // Deploy the policy. The deployer is its owner and fee setter until the handoff below.
    //
    deployment.policy = new V4FeePolicy({owner: deployer, _feeSetter: deployer});

    // ---------------------------------------------------------------------------------------------
    // Transactions 05 onward
    //
    // Assign the rulesets, `ASSIGNMENTS_PER_TRANSACTION` per call.
    //
    ProtocolFeeRulesetAssignment[] memory assignments = _assignments();
    for (uint256 start; start < assignments.length; start += ASSIGNMENTS_PER_TRANSACTION) {
      deployment.policy.batchSetProtocolFeeRulesets(_slice(assignments, start));
    }

    // ---------------------------------------------------------------------------------------------
    // Last two transactions
    //
    // Hand the policy to the governance executor. Set the fee setter first, because only the owner
    // can set it.
    //
    deployment.policy.setFeeSetter(governanceExecutor);
    deployment.policy.transferOwnership(governanceExecutor);
  }

  /// @notice Asserts the deployment against this chain's parameters.
  function _check() internal virtual {
    checkNewPolicy(deployment, params, governanceExecutor);
  }

  /// @notice Writes the deployment to the record.
  function _record() internal virtual {
    _write(Records.V4_FEE_POLICY, address(deployment.policy));
    _write(Records.V4_STATIC_CURVE_RULESET, address(deployment.staticCurveRuleset));
    _write(Records.V4_AGGREGATOR_HOOK_RULESET, address(deployment.aggregatorHookRuleset));
    _write(Records.V4_STABLE_PAIR_HOOK_RULESET, address(deployment.stablePairHookRuleset));
    _write(Records.V4_VOLATILE_PAIR_HOOK_RULESET, address(deployment.volatilePairHookRuleset));
  }

  /// @notice Reads the deployment from the record.
  function _read() internal virtual {
    deployment = readPolicyDeployment(recorder, block.chainid);
  }

  /// @notice Returns the ruleset assignments for `params`.
  /// @dev Hookless pools and `staticCurveHooks` get the static curve ruleset. The aggregator
  ///      hook ruleset also goes at `AGGREGATOR_HOOK_RULESET_KEY`, where aggregator hooks that opt
  ///      in look it up.
  function _assignments() internal view returns (ProtocolFeeRulesetAssignment[] memory list) {
    list = new ProtocolFeeRulesetAssignment[](
      2 + params.aggregatorHooks.length + params.stablePairHooks.length
        + params.volatilePairHooks.length + params.staticCurveHooks.length
    );
    list[0] = ProtocolFeeRulesetAssignment(address(0), deployment.staticCurveRuleset);
    list[1] =
      ProtocolFeeRulesetAssignment(AGGREGATOR_HOOK_RULESET_KEY, deployment.aggregatorHookRuleset);

    uint256 next = 2;
    next = _append(list, next, params.aggregatorHooks, deployment.aggregatorHookRuleset);
    next = _append(list, next, params.stablePairHooks, deployment.stablePairHookRuleset);
    next = _append(list, next, params.volatilePairHooks, deployment.volatilePairHookRuleset);
    _append(list, next, params.staticCurveHooks, deployment.staticCurveRuleset);
  }

  /// @notice Returns up to `ASSIGNMENTS_PER_TRANSACTION` entries of `list` from index `start`.
  function _slice(ProtocolFeeRulesetAssignment[] memory list, uint256 start)
    internal
    pure
    returns (ProtocolFeeRulesetAssignment[] memory part)
  {
    uint256 end = start + ASSIGNMENTS_PER_TRANSACTION;
    if (end > list.length) end = list.length;
    part = new ProtocolFeeRulesetAssignment[](end - start);
    for (uint256 i; i < part.length; i++) {
      part[i] = list[start + i];
    }
  }

  /// @notice Writes an assignment of `ruleset` for each of `hooks` into `list` from index `next`.
  /// @return The index after the last one written.
  function _append(
    ProtocolFeeRulesetAssignment[] memory list,
    uint256 next,
    address[] memory hooks,
    IV4ProtocolFeeRuleset ruleset
  ) internal pure returns (uint256) {
    for (uint256 i; i < hooks.length; i++) {
      list[next++] = ProtocolFeeRulesetAssignment(hooks[i], ruleset);
    }
    return next;
  }

  /// @notice Records `deployment` under `name` for this chain, and logs it.
  function _write(string memory name, address deployed) internal {
    recorder.write({chainId: block.chainid, deploymentName: name, deployment: deployed});
    console.log(name, deployed);
  }

  /// @notice Returns the record file name. Tests override it to keep their records apart.
  function _recordName() internal view virtual returns (string memory) {
    return RECORD_NAME;
  }

  /// @notice Returns the parameter file path.
  function _paramsPath() internal view virtual returns (string memory) {
    return POLICY_PARAMS_JSON;
  }
}

/// @notice Returns the deployment on `chainId` from `recorder`, which must be initialized.
function readPolicyDeployment(Recorder storage recorder, uint256 chainId)
  view
  returns (PolicyDeployment memory)
{
  return PolicyDeployment({
    policy: V4FeePolicy(readRecord(recorder, chainId, Records.V4_FEE_POLICY)),
    staticCurveRuleset: V4StaticCurveRuleset(
      readRecord(recorder, chainId, Records.V4_STATIC_CURVE_RULESET)
    ),
    aggregatorHookRuleset: V4AggregatorHookRuleset(
      readRecord(recorder, chainId, Records.V4_AGGREGATOR_HOOK_RULESET)
    ),
    stablePairHookRuleset: IV4ProtocolFeeRuleset(
      readRecord(recorder, chainId, Records.V4_STABLE_PAIR_HOOK_RULESET)
    ),
    volatilePairHookRuleset: IV4ProtocolFeeRuleset(
      readRecord(recorder, chainId, Records.V4_VOLATILE_PAIR_HOOK_RULESET)
    )
  });
}
