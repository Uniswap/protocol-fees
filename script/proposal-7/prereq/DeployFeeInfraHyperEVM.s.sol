// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {WormholeChainId} from "govkit/constants/WormholeChainId.sol";

import {
  NttManagerNoRateLimiting
} from "lib/native-token-transfers/evm/src/NttManager/NttManagerNoRateLimiting.sol";
import {
  WormholeTransceiver
} from "lib/native-token-transfers/evm/src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";

import {WormholeReleaser} from "../../../src/releasers/WormholeReleaser.sol";
import {
  FeeInfraDeployerWormhole,
  WormholeCreationCode
} from "../../deployers/FeeInfraDeployerWormhole.sol";
import {FeeInfraChecks, FeeInfraAddresses} from "../../shared/FeeInfraChecks.sol";
import {
  FeeInfraParams,
  WormholeInfraParams,
  CONSISTENCY_LEVEL
} from "../../shared/FeeInfraParams.sol";
import {FeeSchedule} from "../../shared/FeeSchedule.sol";
import {Lists} from "../../shared/Lists.sol";
import {WormholeInfraChecks, WormholeInfraAddresses} from "../../shared/WormholeInfraChecks.sol";
import {IWormhole} from "../Interfaces.sol";
import "../params/Constants.sol" as Constants;

// -------------------------------------------------------------------------------------------------
// NOTICE:
//
// HyperEVM produces two kinds of blocks. Small blocks land every second with a 3M gas limit; big
// blocks land once a minute with a 30M limit. Which kind a transaction lands in is a flag on the
// sender's HyperCore account, not a property of the transaction, and the deployer transaction
// below costs about 15M gas. Before broadcasting, the deployer must opt in to big blocks by
// submitting this action to HyperCore:
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
// Everything proposal 4 sent as separate transactions happens inside the constructor of one
// `FeeInfraDeployerWormhole`: synthetic UNI and the NTT stack (steps W.01 through W.15), then the
// TokenJar, releaser, and v3 and v4 adapters (F.00 through F.31). Two transactions leave the
// deployer's key: forge's implicit deployment of the `TransceiverStructs` library, and the
// deployer. Nothing is left half-configured by a failure, and no account other than the deployer
// contract ever holds authority over what it deploys.
//
// The deployer holds no values. Every fee, tier, bucket, rule, and list is built here and passed
// in, so the calldata of the deployment transaction is the whole configuration. The schedule
// comes from `script/shared/FeeSchedule.sol`, the chain's values from `params/`.
//
// The v4 configuration mirrors `script/proposal-6/prereq/DeployV4FeeInfra.s.sol`. The two
// per-chain lists it depends on, hook family assignments and stable-stable pairs, are CSV files
// under `params/hyperevm/`, read at run time through `script/shared/Lists.sol`. Both are
// header-only for HyperEVM, and the deployer skips the step that applies each while its list is
// empty.
//
// ---
//
// `run` asserts the resulting state in its own simulation before it records anything. The
// assertions, in `script/shared/FeeInfraChecks.sol` and `WormholeInfraChecks.sol`, compare what
// the deployer deployed against the params it was given. To apply them to the live chain
// afterwards, from the record alone:
//
// forge script script/proposal-7/prereq/DeployFeeInfraHyperEVM.s.sol --sig "check()"
// --rpc-url hyperevm
//
contract DeployFeeInfraHyperEVM is Script {
  Recorder internal recorder;
  Uniswap internal uniswap;

  FeeInfraDeployerWormhole internal deployer;

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
        chainId: Constants.HyperEVM.CHAIN_ID, deploymentName: Constants.Records.FEE_INFRA_DEPLOYER
      }),
      "already deployed: clear .records/ to redeploy"
    );

    WormholeInfraParams memory w = _wormholeParams();
    FeeInfraParams memory f = _feeParams();
    WormholeCreationCode memory code = _wormholeCreationCode();

    // The constructor requires exactly this much: one message fee for the transceiver's
    // initializer, one for the peer registration.
    uint256 value = 2 * IWormhole(Constants.HyperEVM.WORMHOLE_CORE).messageFee();

    vm.startBroadcast();

    // -----------------------------------------------------------------------------------------
    // Transaction 00
    //
    // (Implicit) Deploy the `TransceiverStructs` external library, which forge links into the
    // creation code read below.

    // -----------------------------------------------------------------------------------------
    // Transaction 01
    //
    // Deploy `FeeInfraDeployerWormhole`, whose constructor does steps W.01 through W.15 and F.00
    // through F.31.
    //
    deployer = new FeeInfraDeployerWormhole{value: value}(w, f, code);

    vm.stopBroadcast();

    _check();
    _record();
  }

  /// @dev Verifies a recorded deployment against the chain the script is pointed at.
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
  function _wormholeParams() internal view returns (WormholeInfraParams memory) {
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
  function _feeParams() internal view returns (FeeInfraParams memory) {
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

  /// @dev The two Wormhole implementations are too large to compile into the deployer, so their
  /// creation code is passed in and the deployer appends the constructor arguments itself. Forge
  /// links the `TransceiverStructs` library into this code and deploys the library as the
  /// transaction before the deployer.
  function _wormholeCreationCode() internal pure returns (WormholeCreationCode memory) {
    return WormholeCreationCode({
      nttManager: type(NttManagerNoRateLimiting).creationCode,
      wormholeTransceiver: type(WormholeTransceiver).creationCode
    });
  }

  /// @dev Reads the deployer back out of the record, and asserts the record agrees with it on
  /// every address, so a stale record fails here rather than in the proposal.
  function _load() internal {
    uint256 chainId = Constants.HyperEVM.CHAIN_ID;

    deployer = FeeInfraDeployerWormhole(
      recorder.read({chainId: chainId, deploymentName: Constants.Records.FEE_INFRA_DEPLOYER})
    );

    _requireRecorded(Constants.Records.SYNTHETIC_NTT_UNI, address(deployer.syntheticNttUni()));
    _requireRecorded(
      Constants.Records.NTT_MANAGER_IMPLEMENTATION, deployer.nttManagerImplementation()
    );
    _requireRecorded(Constants.Records.NTT_MANAGER, deployer.nttManager());
    _requireRecorded(
      Constants.Records.WORMHOLE_TRANSCEIVER_IMPLEMENTATION,
      deployer.wormholeTransceiverImplementation()
    );
    _requireRecorded(Constants.Records.WORMHOLE_TRANSCEIVER, deployer.wormholeTransceiver());
    _requireRecorded(Constants.Records.TOKEN_JAR, address(deployer.tokenJar()));
    _requireRecorded(Constants.Records.RELEASER, address(deployer.releaser()));
    _requireRecorded(Constants.Records.V3_OPEN_FEE_ADAPTER, address(deployer.v3OpenFeeAdapter()));
    _requireRecorded(Constants.Records.V4_FEE_ADAPTER, address(deployer.v4FeeAdapter()));
    _requireRecorded(Constants.Records.V4_FEE_POLICY, address(deployer.v4FeePolicy()));
  }

  function _requireRecorded(string memory name, address deployment) internal view {
    require(
      recorder.read({chainId: Constants.HyperEVM.CHAIN_ID, deploymentName: name}) == deployment,
      string.concat("record.", name)
    );
  }

  /// @dev Asserts the deployment landed in the state the proposal assumes: the deployer holds
  /// nothing, and what it deployed matches the params this script gives it.
  function _check() internal view {
    require(address(deployer).balance == 0, "deployer.balance");

    WormholeInfraChecks.check(
      WormholeInfraAddresses({
        syntheticNttUni: deployer.syntheticNttUni(),
        nttManagerImplementation: deployer.nttManagerImplementation(),
        nttManager: NttManagerNoRateLimiting(deployer.nttManager()),
        wormholeTransceiverImplementation: deployer.wormholeTransceiverImplementation(),
        wormholeTransceiver: WormholeTransceiver(deployer.wormholeTransceiver()),
        releaser: WormholeReleaser(payable(address(deployer.releaser())))
      }),
      _wormholeParams()
    );

    FeeInfraChecks.check(
      FeeInfraAddresses({
        tokenJar: deployer.tokenJar(),
        releaser: deployer.releaser(),
        v3OpenFeeAdapter: deployer.v3OpenFeeAdapter(),
        v4FeeAdapter: deployer.v4FeeAdapter(),
        v4FeePolicy: deployer.v4FeePolicy()
      }),
      _feeParams()
    );
  }

  /// @dev Writes the deployer and its deployments for the proposal to read back, then logs them.
  /// Runs only after `_check`, so nothing reaches the record unless it was verified.
  function _record() internal {
    _write(Constants.Records.FEE_INFRA_DEPLOYER, address(deployer));
    _write(Constants.Records.SYNTHETIC_NTT_UNI, address(deployer.syntheticNttUni()));
    _write(Constants.Records.NTT_MANAGER_IMPLEMENTATION, deployer.nttManagerImplementation());
    _write(Constants.Records.NTT_MANAGER, deployer.nttManager());
    _write(
      Constants.Records.WORMHOLE_TRANSCEIVER_IMPLEMENTATION,
      deployer.wormholeTransceiverImplementation()
    );
    _write(Constants.Records.WORMHOLE_TRANSCEIVER, deployer.wormholeTransceiver());
    _write(Constants.Records.TOKEN_JAR, address(deployer.tokenJar()));
    _write(Constants.Records.RELEASER, address(deployer.releaser()));
    _write(Constants.Records.V3_OPEN_FEE_ADAPTER, address(deployer.v3OpenFeeAdapter()));
    _write(Constants.Records.V4_FEE_ADAPTER, address(deployer.v4FeeAdapter()));
    _write(Constants.Records.V4_FEE_POLICY, address(deployer.v4FeePolicy()));
  }

  function _write(string memory name, address deployment) internal {
    recorder.write({
      chainId: Constants.HyperEVM.CHAIN_ID, deploymentName: name, deployment: deployment
    });
    console.log(name, deployment);
  }
}
