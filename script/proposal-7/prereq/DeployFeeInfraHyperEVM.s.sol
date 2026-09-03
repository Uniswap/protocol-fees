// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Uniswap} from "govkit/types/Uniswap.sol";
import {WormholeChainId} from "govkit/constants/WormholeChainId.sol";

import {
  FeeInfraParams,
  WormholeInfraParams,
  CONSISTENCY_LEVEL
} from "../../shared/FeeInfraParams.sol";
import {FeeSchedule} from "../../shared/FeeSchedule.sol";
import {Lists} from "../../shared/Lists.sol";
import {DeployFeeInfraWormhole} from "./DeployFeeInfraWormhole.sol";
import "../params/Constants.sol" as Constants;

// -------------------------------------------------------------------------------------------------
// NOTICE:
//
// HyperEVM produces two kinds of blocks. Small blocks land every second with a 3M gas limit; big
// blocks land once a minute with a 30M limit. Which kind a transaction lands in is a flag on the
// sender's HyperCore account, not a property of the transaction, and deploying the `NttManager`
// implementation alone costs about 4.5M gas, which no small block can hold. Before broadcasting,
// the deployer must opt in to big blocks by submitting this action to HyperCore:
//
//   {"type": "evmUserModify", "usingBigBlocks": true}
//
// Every transaction from the deployer then waits on the one-minute cadence until the flag is
// unset again, which should happen only after this script has run.
//
// ---
//
// This deployment script necessitates a balance of the native token (Ether's equivalent on
// HyperEVM, HYPE) both to pay for gas **and** to pay for Wormhole core messages. The message fee
// is queried at run time rather than assumed.
//
// cast call 0x7C0faFc4384551f063e05aee704ab943b8B53aB3 "messageFee()(uint256)" --rpc-url
// https://rpc.hyperliquid.xyz/evm
//
// This appears to return `0` on HyperEVM today, matching BNB Chain. Nonetheless, it is queried at
// deploy time so there are no unexpected costs.
//
// ---
//
// This script holds HyperEVM's parameters and nothing else. The work is in `DeployFeeInfra`,
// the fee phase (transactions F.00 through F.31: TokenJar, releaser, v3 and v4 adapters), and in
// `DeployFeeInfraWormhole`, which puts the Wormhole phase in front of it (W.00 through W.15:
// synthetic UNI and the NTT stack) and supplies the releaser that burns through it.
//
// Proposal 4 split this work across three scripts per chain: deploy the Wormhole infra, configure
// it, then deploy and configure the fee infra. BNB Chain, Polygon, and Ethereum all had to be
// brought up against one another and the peer addresses were not known until every chain had
// deployed. Nothing is deployed on the Ethereum side this time, so the peers are known up front
// and everything collapses into a single run.
//
// ---
//
// The v4 configuration mirrors `script/proposal-6/prereq/DeployV4FeeInfra.s.sol`, from
// `script/shared/FeeSchedule.sol`. The two per-chain lists it depends on, hook family assignments
// and stable-stable pairs, are CSV files under `params/hyperevm/`, read at run time through
// `script/shared/Lists.sol`. Both are header-only for HyperEVM, and the transaction that applies
// each is skipped while its list is empty.
//
// ---
//
// `run` asserts the resulting state in its own simulation before it records anything. To apply
// the same assertions to the live chain afterwards, from the record alone:
//
// forge script script/proposal-7/prereq/DeployFeeInfraHyperEVM.s.sol --sig "check()"
// --rpc-url hyperevm
//
contract DeployFeeInfraHyperEVM is DeployFeeInfraWormhole {
  Uniswap internal uniswap;

  function run() external {
    _initialize();

    // The recorder writes only after `_check` passes and never during a dry run, so a record here
    // means an earlier `--broadcast` run simulated cleanly. It does not prove the transactions
    // landed: the recorder writes during simulation, before anything is sent, and `check()` is
    // how to confirm what did. Either way, overwriting the record would strand the proposal on
    // the old addresses while everything downstream reads the new ones. To redeploy,
    // deliberately clear the record.
    require(
      !recorder.exists({
        chainId: Constants.HyperEVM.CHAIN_ID, deploymentName: Constants.Records.SYNTHETIC_NTT_UNI
      }),
      "already deployed: clear .records/ to redeploy"
    );

    vm.startBroadcast();
    _deploy();
    vm.stopBroadcast();

    // Runs only after `_check`, so nothing reaches the record unless it was verified.
    _check();
    _record();
  }

  /// @dev Verifies a recorded deployment against the chain the script is pointed at. `run`
  /// applies the same assertions to its own simulation before recording; this applies them to
  /// live state, reading the deployment out of the record.
  function check() external {
    _initialize();
    _load();
    _check();
  }

  /// @dev Preamble shared by `run` and `check`.
  function _initialize() internal {
    Constants.smokeCheck();

    uniswap.loadLatest();
    recorder.initialize({scriptName: Constants.RECORD_NAME});

    require(block.chainid == Constants.HyperEVM.CHAIN_ID, "not HyperEVM");
  }

  /// @dev Wormhole-related parameters.
  function _wormholeParams() internal view override returns (WormholeInfraParams memory) {
    return WormholeInfraParams({
      wormholeChainId: Constants.HyperEVM.WORMHOLE_CHAIN_ID,
      ethereumWormholeChainId: WormholeChainId.Ethereum,
      wormholeCore: Constants.HyperEVM.WORMHOLE_CORE,
      ethereumNttManager: uniswap.ethereum.nttManager,
      ethereumWormholeTransceiver: uniswap.ethereum.wormholeTransceiver,
      receiver: Constants.HyperEVM.WORMHOLE_RECEIVER,
      consistencyLevel: CONSISTENCY_LEVEL
    });
  }

  /// @dev Bridge-agnostic fee infra parameters: the chain's values from `Constants`, the schedule
  /// from `FeeSchedule`, the lists from `params/hyperevm/`.
  function _feeParams() internal view override returns (FeeInfraParams memory) {
    return FeeInfraParams({
      v3Factory: Constants.HyperEVM.V3_FACTORY,
      poolManager: Constants.HyperEVM.POOL_MANAGER,
      receiver: Constants.HyperEVM.WORMHOLE_RECEIVER,
      releaserThreshold: Constants.HyperEVM.RELEASER_THRESHOLD,
      v3DefaultFee: FeeSchedule.V3_DEFAULT_FEE,
      v3FeeTierDefaults: FeeSchedule.v3FeeTierDefaults(),
      feeBuckets: FeeSchedule.feeBuckets(),
      flagRules: FeeSchedule.flagRules(),
      aggHookFamilyId: FeeSchedule.AGG_HOOK_FAMILY_ID,
      aggHookDefaultFee: FeeSchedule.bothDirections(Constants.HyperEVM.AGG_HOOK_DEFAULT_FEE),
      hookFamilies: Lists.hookFamilies(Constants.HyperEVM.HOOK_FAMILIES_CSV),
      pairClassFees: FeeSchedule.pairClassFees(
        Constants.HyperEVM.STABLE_STABLE_PAIRS_CSV, Constants.HyperEVM.STABLE_STABLE_FEE
      )
    });
  }
}
