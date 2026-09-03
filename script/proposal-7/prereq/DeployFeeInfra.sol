// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Recorder} from "govkit/forge/Recorder.sol";

import {TokenJar} from "../../../src/TokenJar.sol";
import {V3OpenFeeAdapter} from "../../../src/feeAdapters/V3OpenFeeAdapter.sol";
import {V4FeeAdapter} from "../../../src/feeAdapters/V4FeeAdapter.sol";
import {V4FeePolicy} from "../../../src/feeAdapters/V4FeePolicy.sol";
import {IReleaser} from "../../../src/interfaces/IReleaser.sol";
import {IOwned} from "../../../src/interfaces/base/IOwned.sol";
import {FeeInfraChecks, FeeInfraAddresses} from "../../shared/FeeInfraChecks.sol";
import {
  FeeInfraParams,
  V3_TIER_100,
  V3_TIER_500,
  V3_TIER_3000,
  V3_TIER_10000
} from "../../shared/FeeInfraParams.sol";
import {Records} from "../params/Constants.sol";

// -------------------------------------------------------------------------------------------------
// Bringing a chain into the fee ecosystem: the TokenJar, the releaser, the v3 and v4 adapters and
// the v4 policy, their configuration, and handover to governance. The same on every chain except
// for the releaser, which depends on how UNI gets back to Ethereum, so the releaser comes from
// `_deployReleaser`, which a bridge-specific subclass implements. A subclass that also needs its
// own infrastructure, as `DeployFeeInfraWormhole` does, overrides `_deploy`, `_load`, `_check`,
// and `_record` to add it; a chain script calls only those four.
//
// Transactions are numbered `F.00` onward, the fee phase of a deployment.
//
abstract contract DeployFeeInfra is Script {
  Recorder internal recorder;

  TokenJar internal tokenJar;
  IReleaser internal releaser;
  V3OpenFeeAdapter internal v3OpenFeeAdapter;
  V4FeeAdapter internal v4FeeAdapter;
  V4FeePolicy internal v4FeePolicy;

  /// @dev The chain's fee infra parameters, built by the chain script.
  function _feeParams() internal view virtual returns (FeeInfraParams memory);

  /// @dev Deploys the releaser for this chain's bridge, pointed at `_tokenJar`. Transaction F.01.
  /// This contract configures and hands over whatever comes back through `IReleaser`; anything
  /// specific to the releaser's bridge is the subclass's to check.
  function _deployReleaser(address _tokenJar, uint256 _threshold)
    internal
    virtual
    returns (IReleaser);

  /// @dev Everything the chain needs deployed and configured. Runs inside the caller's broadcast.
  function _deploy() internal virtual {
    _deployFeeInfra();
  }

  /// @dev Reads every deployment back out of the record.
  function _load() internal virtual {
    _loadFeeInfra();
  }

  /// @dev Asserts every deployment landed in the state the proposal assumes.
  function _check() internal view virtual {
    _checkFeeInfra();
  }

  /// @dev Writes every deployment to the record, then logs it.
  function _record() internal virtual {
    _recordFeeInfra();
  }

  /// @dev Transactions F.00 through F.31.
  function _deployFeeInfra() internal {
    FeeInfraParams memory p = _feeParams();

    // -----------------------------------------------------------------------------------------
    // Transaction F.00
    //
    // Deploy `TokenJar`.
    //
    tokenJar = new TokenJar();

    // -----------------------------------------------------------------------------------------
    // Transaction F.01
    //
    // Deploy the releaser, through the bridge-specific `_deployReleaser`.
    //
    // Parameters:
    //
    // - `_tokenJar`: `TokenJar`.
    // - `_threshold`: Minimum amount of the releaser's resource required to release.
    //
    releaser = _deployReleaser({_tokenJar: address(tokenJar), _threshold: p.releaserThreshold});

    // -----------------------------------------------------------------------------------------
    // Transaction F.02
    //
    // Set the releaser on `TokenJar`.
    //
    // Parameters:
    //
    // - `_releaser`: The releaser.
    //
    tokenJar.setReleaser({_releaser: address(releaser)});

    // -----------------------------------------------------------------------------------------
    // Transaction F.03
    //
    // Transfer `TokenJar` ownership to governance.
    //
    // Parameters:
    //
    // - `newOwner`: Governance's account on this chain.
    //
    tokenJar.transferOwnership({newOwner: p.receiver});

    // -----------------------------------------------------------------------------------------
    // Transaction F.04
    //
    // Set the releaser's threshold-setter to governance.
    //
    // Parameters:
    //
    // - `newThresholdSetter`: Governance's account on this chain.
    //
    releaser.setThresholdSetter({newThresholdSetter: p.receiver});

    // -----------------------------------------------------------------------------------------
    // Transaction F.05
    //
    // Transfer ownership of the releaser to governance.
    //
    // The releaser needs no further configuration, so it is handed over as soon as the TokenJar
    // knows about it. Each contract below stays with the deployer only for as long as its own
    // configuration requires, keeping the window of deployer-held authority as short as possible.
    //
    // Parameters:
    //
    // - `newOwner`: Governance's account on this chain.
    //
    IOwned(address(releaser)).transferOwnership({newOwner: p.receiver});

    // -----------------------------------------------------------------------------------------
    // Transaction F.06
    //
    // Deploy `V3OpenFeeAdapter`.
    //
    // Parameters:
    //
    // - `_factory`: This chain's Uniswap V3 Factory.
    // - `_tokenJar`: `TokenJar`.
    //
    v3OpenFeeAdapter = new V3OpenFeeAdapter({_factory: p.v3Factory, _tokenJar: address(tokenJar)});

    // -----------------------------------------------------------------------------------------
    // Transaction F.07
    //
    // Set `V3OpenFeeAdapter` fee-setter to the deployer for configuration.
    //
    // Parameters:
    //
    // - `newFeeSetter`: Deployer of the contract (owner).
    //
    // The adapter's `owner` is whoever deployed it, which is the only reliable way to name the
    // deployer: `msg.sender` is the script's sender, not necessarily the broadcaster.
    //
    v3OpenFeeAdapter.setFeeSetter({newFeeSetter: v3OpenFeeAdapter.owner()});

    // -----------------------------------------------------------------------------------------
    // Transaction F.08
    //
    // Set `V3OpenFeeAdapter` default fee.
    //
    // Parameters:
    //
    // - `feeValue`: Default fee value.
    //
    v3OpenFeeAdapter.setDefaultFee({feeValue: p.v3DefaultFee});

    // -----------------------------------------------------------------------------------------
    // Transactions F.09, F.10, F.11, F.12
    //
    // Set `V3OpenFeeAdapter` fee tier defaults.
    //
    // Parameters:
    //
    // - `feeTier`: Fee tier to set.
    // - `feeValue`: Default fee value for the tier.
    //
    v3OpenFeeAdapter.setFeeTierDefault({feeTier: V3_TIER_100, feeValue: p.v3FeeTierDefaults[0]});

    v3OpenFeeAdapter.setFeeTierDefault({feeTier: V3_TIER_500, feeValue: p.v3FeeTierDefaults[1]});

    v3OpenFeeAdapter.setFeeTierDefault({feeTier: V3_TIER_3000, feeValue: p.v3FeeTierDefaults[2]});

    v3OpenFeeAdapter.setFeeTierDefault({feeTier: V3_TIER_10000, feeValue: p.v3FeeTierDefaults[3]});

    // -----------------------------------------------------------------------------------------
    // Transactions F.13, F.14, F.15, F.16
    //
    // Store `V3OpenFeeAdapter` fee tiers.
    //
    // Parameters:
    //
    // - `feeTier`: Fee tiers which can be triggered for update.
    //
    v3OpenFeeAdapter.storeFeeTier({feeTier: V3_TIER_100});

    v3OpenFeeAdapter.storeFeeTier({feeTier: V3_TIER_500});

    v3OpenFeeAdapter.storeFeeTier({feeTier: V3_TIER_3000});

    v3OpenFeeAdapter.storeFeeTier({feeTier: V3_TIER_10000});

    // -----------------------------------------------------------------------------------------
    // Transaction F.17
    //
    // Transfer `V3OpenFeeAdapter` fee-setter permission to governance.
    //
    // Parameters:
    //
    // - `newFeeSetter`: Governance's account on this chain.
    //
    v3OpenFeeAdapter.setFeeSetter({newFeeSetter: p.receiver});

    // -----------------------------------------------------------------------------------------
    // Transaction F.18
    //
    // Transfer `V3OpenFeeAdapter` ownership to governance.
    //
    // Parameters:
    //
    // - `newOwner`: Governance's account on this chain.
    //
    v3OpenFeeAdapter.transferOwnership({newOwner: p.receiver});

    // -----------------------------------------------------------------------------------------
    // Transaction F.19
    //
    // Deploy `V4FeeAdapter`.
    //
    // V4 splits the two contracts: the adapter is what the `PoolManager` calls as its protocol
    // fee controller, and the policy holds the fee schedule the adapter reads.
    //
    // Parameters:
    //
    // - `poolManager`: This chain's Uniswap V4 Pool Manager.
    // - `tokenJar`: `TokenJar`.
    //
    v4FeeAdapter =
      new V4FeeAdapter({poolManager: IPoolManager(p.poolManager), tokenJar: address(tokenJar)});

    // -----------------------------------------------------------------------------------------
    // Transaction F.20
    //
    // Deploy `V4FeePolicy`.
    //
    // Parameters:
    //
    // - `poolManager`: This chain's Uniswap V4 Pool Manager.
    //
    v4FeePolicy = new V4FeePolicy({poolManager: IPoolManager(p.poolManager)});

    // -----------------------------------------------------------------------------------------
    // Transaction F.21
    //
    // Set `V4FeePolicy` on `V4FeeAdapter`.
    //
    // Parameters:
    //
    // - `newPolicy`: `V4FeePolicy`, which holds the fee schedule the adapter reads.
    //
    v4FeeAdapter.setPolicy(v4FeePolicy);

    // -----------------------------------------------------------------------------------------
    // Transaction F.22
    //
    // Set `V4FeePolicy` fee-setter to the deployer for configuration.
    //
    // Parameters:
    //
    // - `newFeeSetter`: Deployer of the contract (owner).
    //
    // Queried from v4FeePolicy rather than `msg.sender`, for the reason given at transaction F.07.
    //
    v4FeePolicy.setFeeSetter(v4FeePolicy.owner());

    // -----------------------------------------------------------------------------------------
    // Transaction F.23
    //
    // Set `V4FeePolicy` fee buckets.
    //
    // Parameters:
    //
    // - `buckets`: Eight `FeeBucket` entries, ordered by ascending `lpFeeFloor`.
    //
    v4FeePolicy.setFeeBuckets(p.feeBuckets);

    // -----------------------------------------------------------------------------------------
    // Transaction F.24
    //
    // Set `V4FeePolicy` flag rules.
    //
    // Parameters:
    //
    // - `rules`: `FlagRule` entries mapping self-reported hook flags to families.
    //
    v4FeePolicy.setFlagRules(p.flagRules);

    // -----------------------------------------------------------------------------------------
    // Transaction F.25
    //
    // Set `V4FeePolicy` aggregator hook family default.
    //
    // Parameters:
    //
    // - `familyId`: Aggregator hook family.
    // - `feeValue`: Aggregator default, already packed into both swap directions.
    //
    v4FeePolicy.setFamilyDefault({familyId: p.aggHookFamilyId, feeValue: p.aggHookDefaultFee});

    // -----------------------------------------------------------------------------------------
    // Transaction F.26
    //
    // Assign `V4FeePolicy` hook families by address. Skipped while the list is empty; the
    // numbering holds either way.
    //
    // Parameters:
    //
    // - `assignments`: One `HookFamilyAssignment` per hook.
    //
    if (p.hookFamilies.length > 0) v4FeePolicy.batchSetHookFamily(p.hookFamilies);
    else console.log("Transaction F.26 skipped: no hook family assignments");

    // -----------------------------------------------------------------------------------------
    // Transaction F.27
    //
    // Set `V4FeePolicy` pair-level fees for the aggregator hook family. Skipped while the list is
    // empty; the numbering holds either way.
    //
    // Parameters:
    //
    // - `assignments`: One `PairClassFeeAssignment` per pair, tokens sorted, fee packed into
    //   both swap directions.
    //
    if (p.pairClassFees.length > 0) v4FeePolicy.batchSetPairClassFee(p.pairClassFees);
    else console.log("Transaction F.27 skipped: no stable-stable pairs");

    // -----------------------------------------------------------------------------------------
    // Transaction F.28
    //
    // Transfer `V4FeePolicy` fee-setter permission to governance.
    //
    // Parameters:
    //
    // - `newFeeSetter`: Governance's account on this chain.
    //
    v4FeePolicy.setFeeSetter(p.receiver);

    // -----------------------------------------------------------------------------------------
    // Transaction F.29
    //
    // Transfer `V4FeePolicy` ownership to governance.
    //
    // Parameters:
    //
    // - `newOwner`: Governance's account on this chain.
    //
    v4FeePolicy.transferOwnership(p.receiver);

    // -----------------------------------------------------------------------------------------
    // Transaction F.30
    //
    // Transfer `V4FeeAdapter` fee-setter permission to governance.
    //
    // Parameters:
    //
    // - `newFeeSetter`: Governance's account on this chain.
    //
    v4FeeAdapter.setFeeSetter(p.receiver);

    // -----------------------------------------------------------------------------------------
    // Transaction F.31
    //
    // Transfer `V4FeeAdapter` ownership to governance.
    //
    // Parameters:
    //
    // - `newOwner`: Governance's account on this chain.
    //
    v4FeeAdapter.transferOwnership(p.receiver);
  }

  /// @dev Reads the fee phase's deployments back out of the record.
  function _loadFeeInfra() internal {
    uint256 chainId = block.chainid;

    tokenJar =
      TokenJar(payable(recorder.read({chainId: chainId, deploymentName: Records.TOKEN_JAR})));
    releaser = IReleaser(recorder.read({chainId: chainId, deploymentName: Records.RELEASER}));
    v3OpenFeeAdapter = V3OpenFeeAdapter(
      recorder.read({chainId: chainId, deploymentName: Records.V3_OPEN_FEE_ADAPTER})
    );
    v4FeeAdapter =
      V4FeeAdapter(recorder.read({chainId: chainId, deploymentName: Records.V4_FEE_ADAPTER}));
    v4FeePolicy =
      V4FeePolicy(recorder.read({chainId: chainId, deploymentName: Records.V4_FEE_POLICY}));
  }

  /// @dev Asserts the fee phase's deployments landed in the state `_feeParams` asks for.
  function _checkFeeInfra() internal view {
    FeeInfraChecks.check(_feeInfraAddresses(), _feeParams());
  }

  function _feeInfraAddresses() internal view returns (FeeInfraAddresses memory) {
    return FeeInfraAddresses({
      tokenJar: tokenJar,
      releaser: releaser,
      v3OpenFeeAdapter: v3OpenFeeAdapter,
      v4FeeAdapter: v4FeeAdapter,
      v4FeePolicy: v4FeePolicy
    });
  }

  /// @dev Writes the fee phase's deployments to the record, then logs them.
  function _recordFeeInfra() internal {
    uint256 chainId = block.chainid;

    recorder.write({
      chainId: chainId, deploymentName: Records.TOKEN_JAR, deployment: address(tokenJar)
    });
    recorder.write({
      chainId: chainId, deploymentName: Records.RELEASER, deployment: address(releaser)
    });
    recorder.write({
      chainId: chainId,
      deploymentName: Records.V3_OPEN_FEE_ADAPTER,
      deployment: address(v3OpenFeeAdapter)
    });
    recorder.write({
      chainId: chainId, deploymentName: Records.V4_FEE_ADAPTER, deployment: address(v4FeeAdapter)
    });
    recorder.write({
      chainId: chainId, deploymentName: Records.V4_FEE_POLICY, deployment: address(v4FeePolicy)
    });

    console.log("TokenJar                          :", address(tokenJar));
    console.log("Releaser                          :", address(releaser));
    console.log("V3OpenFeeAdapter                  :", address(v3OpenFeeAdapter));
    console.log("V4FeeAdapter                      :", address(v4FeeAdapter));
    console.log("V4FeePolicy                       :", address(v4FeePolicy));
  }
}
