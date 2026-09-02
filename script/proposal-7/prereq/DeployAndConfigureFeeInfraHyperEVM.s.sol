// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Recorder} from "govkit/forge/Recorder.sol";

import {TokenJar} from "../../../src/TokenJar.sol";
import {WormholeReleaser} from "../../../src/releasers/WormholeReleaser.sol";
import {V3OpenFeeAdapter} from "../../../src/feeAdapters/V3OpenFeeAdapter.sol";
import {V4FeeAdapter} from "../../../src/feeAdapters/V4FeeAdapter.sol";
import {V4FeePolicy} from "../../../src/feeAdapters/V4FeePolicy.sol";
import {FeeBucket, FlagRule} from "../../../src/interfaces/IV4FeePolicy.sol";
import "../Constants.sol" as Constants;

// V3 protocol fee defaults, the same on every chain where fees are live.
uint8 constant DEFAULT_FEE_100 = (4 << 4) | 4; // 1/4 for 0.01% tier
uint8 constant DEFAULT_FEE_500 = (4 << 4) | 4; // 1/4 for 0.05% tier
uint8 constant DEFAULT_FEE_3000 = (6 << 4) | 6; // 1/6 for 0.30% tier
uint8 constant DEFAULT_FEE_10000 = (6 << 4) | 6; // 1/6 for 1.00% tier

// V4 aggregator hook family, matching proposal 6: a hook whose self-reported flags include bit 11
// is classified into family 11.
uint256 constant AGG_HOOK_FLAGS = 1 << 11;
uint8 constant AGG_HOOK_FAMILY_ID = 11;

// -------------------------------------------------------------------------------------------------
// NOTICE:
//
// This script depends on the following script to have been run:
//
// `script/proposal-7/prereq/DeployWormholeInfraHyperEVM.s.sol:DeployWormholeInfraHyperEVM`
//
// Its deployments are read back out of the record file both scripts share,
// `.records/HyperEVM.json`.
//
// ---
//
// The deployer must still be opted in to HyperEVM big blocks; see the notice in
// `DeployWormholeInfraHyperEVM.s.sol`. The largest deployment here, `V4FeePolicy`, costs about
// 2.2M gas, close enough to the 3M small-block limit that the flag should stay set until this
// script has run.
//
// ---
//
// The V4 half mirrors `script/proposal-6/prereq/DeployV4FeeInfra.s.sol`, with two deliberate
// omissions:
//
//  - The LBP and CCA hook family assignments. Those are per-chain hook address lists and there is
//    no HyperEVM list yet; they can be set later by the fee setter without a redeployment.
//  - The stable-stable pair class fees, for the same reason: the pair list is keyed by token
//    addresses that do not exist on HyperEVM yet. The aggregator family default still applies to
//    every aggregator pool; the pair list only lowers the fee on specific stable pairs.
//
// ---
//
// `run` asserts the resulting state in its own simulation before it records anything. To apply
// the same assertions to the live chain afterwards, from the record alone:
//
// forge script script/proposal-7/prereq/DeployAndConfigureFeeInfraHyperEVM.s.sol --sig "check()"
// --rpc-url hyperevm
//
contract DeployAndConfigureFeeInfraHyperEVM is Script {
  Recorder internal recorder;

  address internal nttManager;
  address internal syntheticNttUni;

  TokenJar internal tokenJar;
  WormholeReleaser internal releaser;
  V3OpenFeeAdapter internal v3OpenFeeAdapter;
  V4FeeAdapter internal v4FeeAdapter;
  V4FeePolicy internal v4FeePolicy;

  function run() external {
    _initialize();

    // The recorder writes only after `_check` passes and never during a dry run, so a record here
    // means an earlier `--broadcast` run simulated cleanly. It does not prove the transactions
    // landed: the recorder writes during simulation, before anything is sent, and `check()` is
    // how to confirm what did. Either way, overwriting the record would leave governance owning
    // one fee stack while the proposal activates another. To redeploy, deliberately clear the
    // record.
    require(
      !recorder.exists({
        chainId: Constants.HyperEVM.CHAIN_ID, deploymentName: Constants.Records.TOKEN_JAR
      }),
      "already deployed: clear .records/ to redeploy"
    );

    _loadWormholeInfra();

    FeeBucket[] memory feeBuckets = _feeBuckets();

    vm.startBroadcast();

    // -----------------------------------------------------------------------------------------
    // Transaction 00
    //
    // Deploy `TokenJar`.
    //
    tokenJar = new TokenJar();

    // -----------------------------------------------------------------------------------------
    // Transaction 01
    //
    // Deploy `WormholeReleaser`.
    //
    // Parameters:
    //
    // - `_nttManager`: HyperEVM NttManager proxy.
    // - `_resource`: HyperEVM SyntheticNttUni.
    // - `_threshold`: Minimum amount of `SyntheticNttUni` required to release.
    // - `_tokenJar`: `TokenJar`.
    //
    releaser = new WormholeReleaser({
      _nttManager: nttManager,
      _resource: syntheticNttUni,
      _threshold: Constants.HyperEVM.RELEASER_THRESHOLD,
      _tokenJar: address(tokenJar)
    });

    // -----------------------------------------------------------------------------------------
    // Transaction 02
    //
    // Set `WormholeReleaser` as the releaser on `TokenJar`.
    //
    // Parameters:
    //
    // - `_releaser`: `WormholeReleaser`.
    //
    tokenJar.setReleaser({_releaser: address(releaser)});

    // -----------------------------------------------------------------------------------------
    // Transaction 03
    //
    // Transfer `TokenJar` ownership to `UniswapWormholeMessageReceiver`.
    //
    // Parameters:
    //
    // - `newOwner`: Governance-owned Wormhole message receiver.
    //
    tokenJar.transferOwnership({newOwner: Constants.HyperEVM.WORMHOLE_RECEIVER});

    // -----------------------------------------------------------------------------------------
    // Transaction 04
    //
    // Set `WormholeReleaser` threshold-setter to `UniswapWormholeMessageReceiver`.
    //
    // Parameters:
    //
    // - `_thresholdSetter`: Governance-owned Wormhole message receiver.
    //
    releaser.setThresholdSetter({_thresholdSetter: Constants.HyperEVM.WORMHOLE_RECEIVER});

    // -----------------------------------------------------------------------------------------
    // Transaction 05
    //
    // Transfer ownership of `WormholeReleaser` to `UniswapWormholeMessageReceiver`.
    //
    // The releaser needs no further configuration, so it is handed over as soon as the TokenJar
    // knows about it. Each contract below stays with the deployer only for as long as its own
    // configuration requires, keeping the window of deployer-held authority as short as possible.
    //
    // Parameters:
    //
    // - `newOwner`: Governance-owned Wormhole message receiver.
    //
    releaser.transferOwnership({newOwner: Constants.HyperEVM.WORMHOLE_RECEIVER});

    // -----------------------------------------------------------------------------------------
    // Transaction 06
    //
    // Deploy `V3OpenFeeAdapter`.
    //
    // Parameters:
    //
    // - `_factory`: HyperEVM Uniswap V3 Factory.
    // - `_tokenJar`: `TokenJar`.
    //
    v3OpenFeeAdapter =
      new V3OpenFeeAdapter({_factory: Constants.HyperEVM.V3_FACTORY, _tokenJar: address(tokenJar)});

    // -----------------------------------------------------------------------------------------
    // Transaction 07
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
    // Transaction 08
    //
    // Set `V3OpenFeeAdapter` default fee.
    //
    // Parameters:
    //
    // - `feeValue`: Default fee value.
    //
    v3OpenFeeAdapter.setDefaultFee({feeValue: DEFAULT_FEE_100});

    // -----------------------------------------------------------------------------------------
    // Transactions 09, 10, 11, 12
    //
    // Set `V3OpenFeeAdapter` fee tier defaults.
    //
    // Parameters:
    //
    // - `feeTier`: Fee tier to set.
    // - `feeValue`: Default fee value for the tier.
    //
    v3OpenFeeAdapter.setFeeTierDefault({feeTier: 100, feeValue: DEFAULT_FEE_100});

    v3OpenFeeAdapter.setFeeTierDefault({feeTier: 500, feeValue: DEFAULT_FEE_500});

    v3OpenFeeAdapter.setFeeTierDefault({feeTier: 3000, feeValue: DEFAULT_FEE_3000});

    v3OpenFeeAdapter.setFeeTierDefault({feeTier: 10_000, feeValue: DEFAULT_FEE_10000});

    // -----------------------------------------------------------------------------------------
    // Transactions 13, 14, 15, 16
    //
    // Store `V3OpenFeeAdapter` fee tiers.
    //
    // Parameters:
    //
    // - `feeTier`: Fee tiers which can be triggered for update.
    //
    v3OpenFeeAdapter.storeFeeTier({feeTier: 100});

    v3OpenFeeAdapter.storeFeeTier({feeTier: 500});

    v3OpenFeeAdapter.storeFeeTier({feeTier: 3000});

    v3OpenFeeAdapter.storeFeeTier({feeTier: 10_000});

    // -----------------------------------------------------------------------------------------
    // Transaction 17
    //
    // Transfer `V3OpenFeeAdapter` fee-setter permission to `UniswapWormholeMessageReceiver`.
    //
    // Parameters:
    //
    // - `newFeeSetter`: Governance-owned Wormhole message receiver.
    //
    v3OpenFeeAdapter.setFeeSetter({newFeeSetter: Constants.HyperEVM.WORMHOLE_RECEIVER});

    // -----------------------------------------------------------------------------------------
    // Transaction 18
    //
    // Transfer `V3OpenFeeAdapter` ownership to `UniswapWormholeMessageReceiver`.
    //
    // Parameters:
    //
    // - `newOwner`: Governance-owned Wormhole message receiver.
    //
    v3OpenFeeAdapter.transferOwnership({newOwner: Constants.HyperEVM.WORMHOLE_RECEIVER});

    // -----------------------------------------------------------------------------------------
    // Transaction 19
    //
    // Deploy `V4FeeAdapter`.
    //
    // V4 splits the two contracts: the adapter is what the `PoolManager` calls as its protocol
    // fee controller, and the policy holds the fee schedule the adapter reads.
    //
    // Parameters:
    //
    // - `poolManager`: HyperEVM Uniswap V4 Pool Manager.
    // - `tokenJar`: `TokenJar`.
    //
    v4FeeAdapter = new V4FeeAdapter({
      poolManager: IPoolManager(Constants.HyperEVM.POOL_MANAGER), tokenJar: address(tokenJar)
    });

    // -----------------------------------------------------------------------------------------
    // Transaction 20
    //
    // Deploy `V4FeePolicy`.
    //
    // Parameters:
    //
    // - `poolManager`: HyperEVM Uniswap V4 Pool Manager.
    //
    v4FeePolicy = new V4FeePolicy({poolManager: IPoolManager(Constants.HyperEVM.POOL_MANAGER)});

    // -----------------------------------------------------------------------------------------
    // Transaction 21
    //
    // Set `V4FeePolicy` on `V4FeeAdapter`.
    //
    // Parameters:
    //
    // - `newPolicy`: `V4FeePolicy`, which holds the fee schedule the adapter reads.
    //
    v4FeeAdapter.setPolicy(v4FeePolicy);

    // -----------------------------------------------------------------------------------------
    // Transaction 22
    //
    // Set `V4FeePolicy` fee-setter to the deployer for configuration.
    //
    // Parameters:
    //
    // - `newFeeSetter`: Deployer of the contract (owner).
    //
    // Queried from v4FeePolicy rather than `msg.sender`, for the reason given at transaction 07.
    //
    v4FeePolicy.setFeeSetter(v4FeePolicy.owner());

    // -----------------------------------------------------------------------------------------
    // Transaction 23
    //
    // Set `V4FeePolicy` fee buckets. Identical to every chain configured by proposal 6.
    //
    // Parameters:
    //
    // - `buckets`: Eight `FeeBucket` entries, ordered by ascending `lpFeeFloor`.
    //
    v4FeePolicy.setFeeBuckets(feeBuckets);

    // -----------------------------------------------------------------------------------------
    // Transaction 24
    //
    // Set `V4FeePolicy` flag rules. Aggregator hooks are the one hook family with a fee rule,
    // keyed off hook flag 11.
    //
    // | Name             | Family ID | Required flags |
    // | ---------------- | --------- | -------------- |
    // | Aggregator Hooks | `11`      | `1 << 11`      |
    //
    // Parameters:
    //
    // - `rules`: One `FlagRule` mapping the aggregator flag to family 11.
    //
    FlagRule[] memory flagRules = new FlagRule[](1);
    flagRules[0] = FlagRule({requiredFlags: AGG_HOOK_FLAGS, familyId: AGG_HOOK_FAMILY_ID});
    v4FeePolicy.setFlagRules(flagRules);

    // -----------------------------------------------------------------------------------------
    // Transaction 25
    //
    // Set `V4FeePolicy` aggregator hook family default.
    //
    // Parameters:
    //
    // - `familyId`: Aggregator hook family.
    // - `feeValue`: Aggregator default, packed into both swap directions.
    //
    v4FeePolicy.setFamilyDefault({
      familyId: AGG_HOOK_FAMILY_ID,
      feeValue: _bothDirections(Constants.HyperEVM.AGG_HOOK_DEFAULT_FEE)
    });

    // -----------------------------------------------------------------------------------------
    // Not set yet:
    //
    //  - `batchSetHookFamily`, assigning LBP and CCA hooks to family 255. No HyperEVM hooks exist
    //    yet to list.
    //  - `batchSetPairClassFee`, discounting stable-stable aggregator pairs. Potential candidates
    //    exist on HyperEVM, but the list has not been chosen.
    //
    // Both are `onlyFeeSetter`, so adding either here means adding it above transaction 26.
    // Afterwards they are governance actions needing no redeployment.
    //
    // -----------------------------------------------------------------------------------------
    // Transaction 26
    //
    // Transfer `V4FeePolicy` fee-setter permission to `UniswapWormholeMessageReceiver`.
    //
    // Parameters:
    //
    // - `newFeeSetter`: Governance-owned Wormhole message receiver.
    //
    v4FeePolicy.setFeeSetter(Constants.HyperEVM.WORMHOLE_RECEIVER);

    // -----------------------------------------------------------------------------------------
    // Transaction 27
    //
    // Transfer `V4FeePolicy` ownership to `UniswapWormholeMessageReceiver`.
    //
    // Parameters:
    //
    // - `newOwner`: Governance-owned Wormhole message receiver.
    //
    v4FeePolicy.transferOwnership(Constants.HyperEVM.WORMHOLE_RECEIVER);

    // -----------------------------------------------------------------------------------------
    // Transaction 28
    //
    // Transfer `V4FeeAdapter` fee-setter permission to `UniswapWormholeMessageReceiver`.
    //
    // Parameters:
    //
    // - `newFeeSetter`: Governance-owned Wormhole message receiver.
    //
    v4FeeAdapter.setFeeSetter(Constants.HyperEVM.WORMHOLE_RECEIVER);

    // -----------------------------------------------------------------------------------------
    // Transaction 29
    //
    // Transfer `V4FeeAdapter` ownership to `UniswapWormholeMessageReceiver`.
    //
    // Parameters:
    //
    // - `newOwner`: Governance-owned Wormhole message receiver.
    //
    v4FeeAdapter.transferOwnership(Constants.HyperEVM.WORMHOLE_RECEIVER);

    vm.stopBroadcast();

    _check(feeBuckets);
    _record();
  }

  /// @dev Verifies a recorded deployment against the chain the script is pointed at. `run`
  /// applies the same assertions to its own simulation before recording; this applies them to
  /// live state, reading the deployment out of the record.
  function check() external {
    _initialize();
    _loadWormholeInfra();
    _loadFeeInfra();
    _check(_feeBuckets());
  }

  /// @dev Preamble shared by `run` and `check`.
  function _initialize() internal {
    Constants.smokeCheck();

    recorder.initialize({scriptName: Constants.RECORD_NAME});

    require(block.chainid == Constants.HyperEVM.CHAIN_ID, "not HyperEVM");
  }

  /// @dev Reads the Wormhole infra this script builds on out of the record.
  function _loadWormholeInfra() internal {
    uint256 chainId = Constants.HyperEVM.CHAIN_ID;

    nttManager = recorder.read({chainId: chainId, deploymentName: Constants.Records.NTT_MANAGER});
    syntheticNttUni =
      recorder.read({chainId: chainId, deploymentName: Constants.Records.SYNTHETIC_NTT_UNI});
  }

  /// @dev Reads this script's own deployments out of the record.
  function _loadFeeInfra() internal {
    uint256 chainId = Constants.HyperEVM.CHAIN_ID;

    tokenJar = TokenJar(
      payable(recorder.read({chainId: chainId, deploymentName: Constants.Records.TOKEN_JAR}))
    );
    releaser = WormholeReleaser(
      payable(recorder.read({chainId: chainId, deploymentName: Constants.Records.RELEASER}))
    );
    v3OpenFeeAdapter = V3OpenFeeAdapter(
      recorder.read({chainId: chainId, deploymentName: Constants.Records.V3_OPEN_FEE_ADAPTER})
    );
    v4FeeAdapter = V4FeeAdapter(
      recorder.read({chainId: chainId, deploymentName: Constants.Records.V4_FEE_ADAPTER})
    );
    v4FeePolicy = V4FeePolicy(
      recorder.read({chainId: chainId, deploymentName: Constants.Records.V4_FEE_POLICY})
    );
  }

  /// @dev Fee buckets, identical to every chain configured by proposal 6.
  function _feeBuckets() internal pure returns (FeeBucket[] memory buckets) {
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

  /// @dev Packs one fee into both swap directions of a v4 protocol fee: the lower 12 bits apply
  /// to zero-for-one swaps and the upper 12 bits to one-for-zero.
  function _bothDirections(uint24 fee) internal pure returns (uint24) {
    return fee << 12 | fee;
  }

  /// @dev Asserts the deployment landed in the state the proposal assumes.
  function _check(FeeBucket[] memory feeBuckets) internal view {
    address receiver = Constants.HyperEVM.WORMHOLE_RECEIVER;
    address poolManager = Constants.HyperEVM.POOL_MANAGER;

    // TokenJar
    require(tokenJar.releaser() == address(releaser), "tokenJar.releaser");
    require(tokenJar.owner() == receiver, "tokenJar.owner");

    // WormholeReleaser
    require(address(releaser.NTT_MANAGER()) == nttManager, "releaser.nttManager");
    require(address(releaser.RESOURCE()) == syntheticNttUni, "releaser.resource");
    require(address(releaser.TOKEN_JAR()) == address(tokenJar), "releaser.tokenJar");
    require(releaser.threshold() == Constants.HyperEVM.RELEASER_THRESHOLD, "releaser.threshold");
    require(releaser.thresholdSetter() == receiver, "releaser.thresholdSetter");
    require(releaser.owner() == receiver, "releaser.owner");

    // V3OpenFeeAdapter
    require(
      address(v3OpenFeeAdapter.FACTORY()) == Constants.HyperEVM.V3_FACTORY,
      "v3OpenFeeAdapter.factory"
    );
    require(v3OpenFeeAdapter.TOKEN_JAR() == address(tokenJar), "v3OpenFeeAdapter.tokenJar");
    require(v3OpenFeeAdapter.defaultFee() == DEFAULT_FEE_100, "v3OpenFeeAdapter.defaultFee");
    require(
      v3OpenFeeAdapter.feeTierDefaults(100) == DEFAULT_FEE_100,
      "v3OpenFeeAdapter.feeTierDefault.100"
    );
    require(
      v3OpenFeeAdapter.feeTierDefaults(500) == DEFAULT_FEE_500,
      "v3OpenFeeAdapter.feeTierDefault.500"
    );
    require(
      v3OpenFeeAdapter.feeTierDefaults(3000) == DEFAULT_FEE_3000,
      "v3OpenFeeAdapter.feeTierDefault.3000"
    );
    require(
      v3OpenFeeAdapter.feeTierDefaults(10_000) == DEFAULT_FEE_10000,
      "v3OpenFeeAdapter.feeTierDefault.10000"
    );

    // `feeTiers` is a public array with no length getter, so the four tiers are checked by index.
    // `storeFeeTier` rejects duplicates but is permissionless, so a longer array is possible and
    // harmless: `triggerFeeUpdate` walks it and every entry resolves through the defaults above.
    require(v3OpenFeeAdapter.feeTiers(0) == 100, "v3OpenFeeAdapter.feeTiers.0");
    require(v3OpenFeeAdapter.feeTiers(1) == 500, "v3OpenFeeAdapter.feeTiers.1");
    require(v3OpenFeeAdapter.feeTiers(2) == 3000, "v3OpenFeeAdapter.feeTiers.2");
    require(v3OpenFeeAdapter.feeTiers(3) == 10_000, "v3OpenFeeAdapter.feeTiers.3");

    require(v3OpenFeeAdapter.feeSetter() == receiver, "v3OpenFeeAdapter.feeSetter");
    require(v3OpenFeeAdapter.owner() == receiver, "v3OpenFeeAdapter.owner");

    // V4FeeAdapter
    require(address(v4FeeAdapter.POOL_MANAGER()) == poolManager, "v4FeeAdapter.poolManager");
    require(v4FeeAdapter.TOKEN_JAR() == address(tokenJar), "v4FeeAdapter.tokenJar");
    require(address(v4FeeAdapter.policy()) == address(v4FeePolicy), "v4FeeAdapter.policy");
    require(v4FeeAdapter.feeSetter() == receiver, "v4FeeAdapter.feeSetter");
    require(v4FeeAdapter.owner() == receiver, "v4FeeAdapter.owner");

    // V4FeePolicy
    require(address(v4FeePolicy.POOL_MANAGER()) == poolManager, "v4FeePolicy.poolManager");

    // While this is not something we set in this script, leaving the global default at zero is
    // deliberate: a non-zero value would charge every v4 pool, not just the aggregator family
    // configured below.
    require(v4FeePolicy.defaultFee() == 0, "v4FeePolicy.defaultFee");

    require(v4FeePolicy.feeBucketsLength() == feeBuckets.length, "v4FeePolicy.feeBucketsLength");
    require(v4FeePolicy.flagRulesLength() == 1, "v4FeePolicy.flagRulesLength");
    require(
      v4FeePolicy.familyDefaults(AGG_HOOK_FAMILY_ID)
        == _bothDirections(Constants.HyperEVM.AGG_HOOK_DEFAULT_FEE),
      "v4FeePolicy.familyDefaults"
    );
    require(v4FeePolicy.feeSetter() == receiver, "v4FeePolicy.feeSetter");
    require(v4FeePolicy.owner() == receiver, "v4FeePolicy.owner");

    for (uint256 i; i < feeBuckets.length; i++) {
      (uint24 lpFeeFloor, uint24 alphaPips, uint32 betaPips) = v4FeePolicy.feeBucket(i);
      require(lpFeeFloor == feeBuckets[i].lpFeeFloor, "v4FeePolicy.feeBucket.lpFeeFloor");
      require(alphaPips == feeBuckets[i].alphaPips, "v4FeePolicy.feeBucket.alphaPips");
      require(betaPips == feeBuckets[i].betaPips, "v4FeePolicy.feeBucket.betaPips");
    }

    (uint256 requiredFlags, uint8 familyId) = v4FeePolicy.flagRules(0);
    require(requiredFlags == AGG_HOOK_FLAGS, "v4FeePolicy.flagRules.requiredFlags");
    require(familyId == AGG_HOOK_FAMILY_ID, "v4FeePolicy.flagRules.familyId");
  }

  /// @dev Writes the deployments for the proposal to read back, then logs them. Runs only after
  /// `_check`, so nothing reaches the record unless it was verified.
  function _record() internal {
    uint256 chainId = Constants.HyperEVM.CHAIN_ID;

    recorder.write({
      chainId: chainId, deploymentName: Constants.Records.TOKEN_JAR, deployment: address(tokenJar)
    });
    recorder.write({
      chainId: chainId, deploymentName: Constants.Records.RELEASER, deployment: address(releaser)
    });
    recorder.write({
      chainId: chainId,
      deploymentName: Constants.Records.V3_OPEN_FEE_ADAPTER,
      deployment: address(v3OpenFeeAdapter)
    });
    recorder.write({
      chainId: chainId,
      deploymentName: Constants.Records.V4_FEE_ADAPTER,
      deployment: address(v4FeeAdapter)
    });
    recorder.write({
      chainId: chainId,
      deploymentName: Constants.Records.V4_FEE_POLICY,
      deployment: address(v4FeePolicy)
    });

    console.log("TokenJar        :", address(tokenJar));
    console.log("WormholeReleaser:", address(releaser));
    console.log("V3OpenFeeAdapter:", address(v3OpenFeeAdapter));
    console.log("V4FeeAdapter    :", address(v4FeeAdapter));
    console.log("V4FeePolicy     :", address(v4FeePolicy));
  }
}
