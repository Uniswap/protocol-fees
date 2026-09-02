// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {ERC1967Reader} from "govkit/forge/ERC1967Reader.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {WormholeChainId} from "govkit/constants/WormholeChainId.sol";
import {WormholeEncoder} from "govkit/bridges/WormholeEncoder.sol";

import {
  NttManagerNoRateLimiting
} from "lib/native-token-transfers/evm/src/NttManager/NttManagerNoRateLimiting.sol";
import {IManagerBase} from "lib/native-token-transfers/evm/src/interfaces/IManagerBase.sol";
import {
  WormholeTransceiver
} from "lib/native-token-transfers/evm/src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {SyntheticNttUni} from "../../../src/wormhole/SyntheticNttUni.sol";
import {TokenJar} from "../../../src/TokenJar.sol";
import {WormholeReleaser} from "../../../src/releasers/WormholeReleaser.sol";
import {V3OpenFeeAdapter} from "../../../src/feeAdapters/V3OpenFeeAdapter.sol";
import {V4FeeAdapter} from "../../../src/feeAdapters/V4FeeAdapter.sol";
import {V4FeePolicy} from "../../../src/feeAdapters/V4FeePolicy.sol";
import {
  FeeBucket,
  FlagRule,
  HookFamilyAssignment,
  PairClassFeeAssignment
} from "../../../src/interfaces/IV4FeePolicy.sol";
import {Lists, Pair} from "../../shared/Lists.sol";
import {IWormhole} from "../Interfaces.sol";
import "../params/Constants.sol" as Constants;

/// @dev Consistency level 202 is what Wormhole's own deployment scripts use; the three
/// custom-consistency parameters are only read when the level is 203.
uint8 constant CONSISTENCY_LEVEL = 202;

/// @dev Number of transceivers that must attest to a message before the manager executes it.
/// Registering the first transceiver raises it from 0 to 1, and the manager rejects any value
/// above the number of enabled transceivers, so with one transceiver 1 is the only value it can
/// hold. Never set explicitly; asserted by `_check`.
uint8 constant TRANSCEIVER_THRESHOLD = 1;

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
// Proposal 4 split this work across three scripts per chain: deploy the Wormhole infra, configure
// it, then deploy and configure the fee infra. BNB Chain, Polygon, and Ethereum all had to be
// brought up against one another and the peer addresses were not known until every chain had
// deployed. Nothing is deployed on the Ethereum side this time, so the peers are known up front
// and everything collapses into a single run.
//
// ---
//
// The v4 configuration mirrors `script/proposal-6/prereq/DeployV4FeeInfra.s.sol`. The two
// per-chain lists it depends on, hook family assignments and stable-stable pairs, are CSV files
// under `params/hyperevm/`, read at run time through `script/shared/Lists.sol`. Both are
// header-only for HyperEVM, and the transaction that applies each is skipped while its list is
// empty.
//
// ---
//
// `run` asserts the resulting state in its own simulation before it records anything. To apply
// the same assertions to the live chain afterwards, from the record alone:
//
// forge script script/proposal-7/prereq/DeployFeeInfraHyperEVM.s.sol --sig "check()"
// --rpc-url hyperevm
//
contract DeployFeeInfraHyperEVM is Script {
  Recorder internal recorder;
  Uniswap internal uniswap;

  SyntheticNttUni internal syntheticNttUni;

  address internal nttManagerImplementation;
  NttManagerNoRateLimiting internal nttManager;

  address internal wormholeTransceiverImplementation;
  WormholeTransceiver internal wormholeTransceiver;

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
    // how to confirm what did. Either way, overwriting the record would strand the proposal on
    // the old addresses while everything downstream reads the new ones. To redeploy,
    // deliberately clear the record.
    require(
      !recorder.exists({
        chainId: Constants.HyperEVM.CHAIN_ID, deploymentName: Constants.Records.SYNTHETIC_NTT_UNI
      }),
      "already deployed: clear .records/ to redeploy"
    );

    FeeBucket[] memory feeBuckets = _feeBuckets();
    HookFamilyAssignment[] memory hookFamilies = _hookFamilies();
    PairClassFeeAssignment[] memory pairClassFees = _pairClassFees();

    vm.startBroadcast();

    // -----------------------------------------------------------------------------------------
    // Transaction 00
    //
    // (Implicit) Deploy the `TransceiverStructs` external library for wormhole contracts.

    // -----------------------------------------------------------------------------------------
    // Transaction 01
    //
    // Deploy `SyntheticNttUni`.
    //
    syntheticNttUni = new SyntheticNttUni();

    // -----------------------------------------------------------------------------------------
    // Transaction 02
    //
    // Deploy `NttManager` implementation with no rate limiting.
    //
    // Parameters:
    //
    // - `_token`: HyperEVM deployment of UNI (`SyntheticNttUni`).
    // - `_mode`: `BURNING` for all foreign chains.
    // - `_chainId`: Wormhole-defined chain ID, not EIP155-defined.
    //
    nttManagerImplementation = address(
      new NttManagerNoRateLimiting({
        _token: address(syntheticNttUni),
        _mode: IManagerBase.Mode.BURNING,
        _chainId: Constants.HyperEVM.WORMHOLE_CHAIN_ID
      })
    );

    // -----------------------------------------------------------------------------------------
    // Transaction 03
    //
    // Deploy `NttManager` proxy and set its implementation.
    //
    // We generally avoid using proxy-implementation pairs. Since Wormhole has only defined a
    // collection of NttManager systems as proxy implementations, though, it will be best to use
    // their code and simply avoid any potential mishaps on our end.
    //
    // Transactions 12 through 15 transfer the full authority to the governance receiver contract
    // to mitigate upgrade authority risk.
    //
    // Parameters:
    //
    // - `implementation`: Implementation contract address.
    // - `_data`: Optional call to make during deployment. We dont use this.
    //
    nttManager = NttManagerNoRateLimiting(
      address(new ERC1967Proxy({implementation: nttManagerImplementation, _data: new bytes(0)}))
    );

    // -----------------------------------------------------------------------------------------
    // Transaction 04
    //
    // Initialize `NttManager` proxy.
    //
    nttManager.initialize();

    // -----------------------------------------------------------------------------------------
    // Transaction 05
    //
    // Deploy `WormholeTransceiver` implementation.
    //
    // The transceiver is the messaging layer and the manager is the token layer, but the
    // transceiver takes the manager as a constructor argument, so it must be deployed second.
    //
    // Parameters:
    //
    // - `nttManager`: NttManager proxy address.
    // - `wormholeCoreBridge`: HyperEVM Wormhole core bridge.
    // - `_consistencyLevel`: Hardcoded to 202 in Wormhole documentation [1].
    // - `_customConsistencyLevel`: Unused when `_consistencyLevel != 203` [2].
    // - `_additionalBlocks`: Unused when `_consistencyLevel != 203` [2].
    // - `_customConsistencyLevelAddress`: Unused when `_consistencyLevel != 203` [2].
    //
    // Sources:
    //
    // [1]
    // https://wormhole.com/docs/products/token-transfers/native-token-transfers/guides/deploy-to-evm/#ntt-manager-deployment-parameters
    // [2]
    // https://github.com/wormhole-foundation/wormhole/blob/main/whitepapers/0001_generic_message_passing.md#custom-handling
    // 
    wormholeTransceiverImplementation = address(
      new WormholeTransceiver({
        nttManager: address(nttManager),
        wormholeCoreBridge: Constants.HyperEVM.WORMHOLE_CORE,
        _consistencyLevel: CONSISTENCY_LEVEL,
        _customConsistencyLevel: 0,
        _additionalBlocks: 0,
        _customConsistencyLevelAddress: address(0x00)
      })
    );

    // -----------------------------------------------------------------------------------------
    // Transaction 06
    //
    // Deploy `WormholeTransceiver` proxy.
    //
    // Parameters:
    //
    // - `implementation`: Implementation contract address.
    // - `_data`: Optional call to make during deployment. We dont use this.
    //
    wormholeTransceiver = WormholeTransceiver(
      address(
        new ERC1967Proxy({implementation: wormholeTransceiverImplementation, _data: new bytes(0)})
      )
    );

    // -----------------------------------------------------------------------------------------
    // Query for Wormhole Message Fee.
    //
    uint256 messageFee = IWormhole(Constants.HyperEVM.WORMHOLE_CORE).messageFee();

    // -----------------------------------------------------------------------------------------
    // Transaction 07
    //
    // Initialize `WormholeTransceiver` proxy with a recently queried `messageFee`.
    //
    // Parameters:
    //
    // - `value`: Call value for a call to `wormhole.publishMessage` in the initializer.
    //
    wormholeTransceiver.initialize{value: messageFee}();

    // -----------------------------------------------------------------------------------------
    // Transaction 08
    //
    // Set `NttManager` proxy's transceiver to the `WormholeTransceiver` proxy. Registering the
    // first transceiver also raises the attestation threshold from 0 to 1.
    //
    // Parameters:
    //
    // - `transceiver`: WormholeTransceiver proxy.
    //
    nttManager.setTransceiver({transceiver: address(wormholeTransceiver)});

    // -----------------------------------------------------------------------------------------
    // Transaction 09
    //
    // Set `SyntheticNttUni` mint authority to `NttManager` proxy.
    //
    // Parameters:
    //
    // - `newNtt`: NttManager proxy.
    //
    syntheticNttUni.setNtt({newNtt: address(nttManager)});

    // -----------------------------------------------------------------------------------------
    // Transaction 10
    //
    // Set Ethereum `WormholeTransceiver` proxy as a peer on the Ethereum Chain Id.
    //
    // The Ethereum contracts already exist and are owned by the Timelock, so the matching
    // registration in the other direction is the governance half of this proposal.
    //
    // Parameters:
    //
    // - `peerChainId`: Wormhole-defined Ethereum Chain Id.
    // - `peerContract`: Ethereum WormholeTransceiver proxy.
    //
    wormholeTransceiver.setWormholePeer{value: messageFee}({
      peerChainId: WormholeChainId.Ethereum,
      peerContract: WormholeEncoder.toWormholeFormat(uniswap.ethereum.wormholeTransceiver)
    });

    // -----------------------------------------------------------------------------------------
    // Transaction 11
    //
    // Set the `NttManager` proxy on Ethereum as a peer.
    //
    // Parameters:
    //
    // - `peerChainId`: Wormhole-defined Ethereum Chain Id.
    // - `peerContract`: Ethereum NttManager proxy.
    // - `decimals`: UNI decimals on Ethereum.
    // - `inboundLimit`: Set to zero when rate limiter is disabled [1].
    //
    // Sources:
    //
    // [1] https://github.com/wormhole-foundation/native-token-transfers/blob/main/evm/README.md
    //
    nttManager.setPeer({
      peerChainId: WormholeChainId.Ethereum,
      peerContract: WormholeEncoder.toWormholeFormat(uniswap.ethereum.nttManager),
      decimals: 18,
      inboundLimit: 0
    });

    // -----------------------------------------------------------------------------------------
    // Transaction 12
    //
    // Transfer ownership of `SyntheticNttUni` to governance.
    //
    // Parameters:
    //
    // - `newOwner`: Governance-owned Wormhole message receiver.
    //
    syntheticNttUni.transferOwnership({newOwner: Constants.HyperEVM.WORMHOLE_RECEIVER});

    // -----------------------------------------------------------------------------------------
    // Transaction 13
    //
    // Transfer `NttManager` proxy ownership to `UniswapWormholeMessageReceiver`. This call also
    // iterates registered transceivers and forwards the ownership transfer to each via
    // `transferTransceiverOwnership` (`onlyNttManager`), so the `WormholeTransceiver` proxy ends
    // up owned by the same address without an explicit second transfer.
    //
    // Parameters:
    //
    // - `newOwner`: Governance-owned Wormhole message receiver.
    //
    nttManager.transferOwnership({newOwner: Constants.HyperEVM.WORMHOLE_RECEIVER});

    // -----------------------------------------------------------------------------------------
    // Transaction 14
    //
    // Renounce pauser capability on the `WormholeTransceiver` proxy.
    //
    // The deployer is set as the pauser during proxy initialization and is independent of
    // ownership. Even after ownership transfer, the deployer remains the pauser unless the
    // capability is transferred (or renounced). We renounce by setting the pauser to the zero
    // address so no party can pause the transceiver going forward.
    //
    // Parameters:
    //
    // - `newPauser`: Zero address, renouncing the capability.
    //
    wormholeTransceiver.transferPauserCapability(address(0));

    // -----------------------------------------------------------------------------------------
    // Transaction 15
    //
    // Renounce pauser capability on the `NttManager` proxy. Same rationale as the transceiver.
    //
    // Parameters:
    //
    // - `newPauser`: Zero address, renouncing the capability.
    //
    nttManager.transferPauserCapability(address(0));

    // -----------------------------------------------------------------------------------------
    // Transaction 16
    //
    // Deploy `TokenJar`.
    //
    tokenJar = new TokenJar();

    // -----------------------------------------------------------------------------------------
    // Transaction 17
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
      _nttManager: address(nttManager),
      _resource: address(syntheticNttUni),
      _threshold: Constants.HyperEVM.RELEASER_THRESHOLD,
      _tokenJar: address(tokenJar)
    });

    // -----------------------------------------------------------------------------------------
    // Transaction 18
    //
    // Set `WormholeReleaser` as the releaser on `TokenJar`.
    //
    // Parameters:
    //
    // - `_releaser`: `WormholeReleaser`.
    //
    tokenJar.setReleaser({_releaser: address(releaser)});

    // -----------------------------------------------------------------------------------------
    // Transaction 19
    //
    // Transfer `TokenJar` ownership to `UniswapWormholeMessageReceiver`.
    //
    // Parameters:
    //
    // - `newOwner`: Governance-owned Wormhole message receiver.
    //
    tokenJar.transferOwnership({newOwner: Constants.HyperEVM.WORMHOLE_RECEIVER});

    // -----------------------------------------------------------------------------------------
    // Transaction 20
    //
    // Set `WormholeReleaser` threshold-setter to `UniswapWormholeMessageReceiver`.
    //
    // Parameters:
    //
    // - `_thresholdSetter`: Governance-owned Wormhole message receiver.
    //
    releaser.setThresholdSetter({_thresholdSetter: Constants.HyperEVM.WORMHOLE_RECEIVER});

    // -----------------------------------------------------------------------------------------
    // Transaction 21
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
    // Transaction 22
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
    // Transaction 23
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
    // Transaction 24
    //
    // Set `V3OpenFeeAdapter` default fee.
    //
    // Parameters:
    //
    // - `feeValue`: Default fee value.
    //
    v3OpenFeeAdapter.setDefaultFee({feeValue: DEFAULT_FEE_100});

    // -----------------------------------------------------------------------------------------
    // Transactions 25, 26, 27, 28
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
    // Transactions 29, 30, 31, 32
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
    // Transaction 33
    //
    // Transfer `V3OpenFeeAdapter` fee-setter permission to `UniswapWormholeMessageReceiver`.
    //
    // Parameters:
    //
    // - `newFeeSetter`: Governance-owned Wormhole message receiver.
    //
    v3OpenFeeAdapter.setFeeSetter({newFeeSetter: Constants.HyperEVM.WORMHOLE_RECEIVER});

    // -----------------------------------------------------------------------------------------
    // Transaction 34
    //
    // Transfer `V3OpenFeeAdapter` ownership to `UniswapWormholeMessageReceiver`.
    //
    // Parameters:
    //
    // - `newOwner`: Governance-owned Wormhole message receiver.
    //
    v3OpenFeeAdapter.transferOwnership({newOwner: Constants.HyperEVM.WORMHOLE_RECEIVER});

    // -----------------------------------------------------------------------------------------
    // Transaction 35
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
    // Transaction 36
    //
    // Deploy `V4FeePolicy`.
    //
    // Parameters:
    //
    // - `poolManager`: HyperEVM Uniswap V4 Pool Manager.
    //
    v4FeePolicy = new V4FeePolicy({poolManager: IPoolManager(Constants.HyperEVM.POOL_MANAGER)});

    // -----------------------------------------------------------------------------------------
    // Transaction 37
    //
    // Set `V4FeePolicy` on `V4FeeAdapter`.
    //
    // Parameters:
    //
    // - `newPolicy`: `V4FeePolicy`, which holds the fee schedule the adapter reads.
    //
    v4FeeAdapter.setPolicy(v4FeePolicy);

    // -----------------------------------------------------------------------------------------
    // Transaction 38
    //
    // Set `V4FeePolicy` fee-setter to the deployer for configuration.
    //
    // Parameters:
    //
    // - `newFeeSetter`: Deployer of the contract (owner).
    //
    // Queried from v4FeePolicy rather than `msg.sender`, for the reason given at transaction 23.
    //
    v4FeePolicy.setFeeSetter(v4FeePolicy.owner());

    // -----------------------------------------------------------------------------------------
    // Transaction 39
    //
    // Set `V4FeePolicy` fee buckets. Identical to every chain configured by proposal 6.
    //
    // Parameters:
    //
    // - `buckets`: Eight `FeeBucket` entries, ordered by ascending `lpFeeFloor`.
    //
    v4FeePolicy.setFeeBuckets(feeBuckets);

    // -----------------------------------------------------------------------------------------
    // Transaction 40
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
    // Transaction 41
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
    // Transaction 42
    //
    // Assign `V4FeePolicy` hook families by address, from `HOOK_FAMILIES_CSV`. Skipped while that
    // list is empty; the numbering holds either way.
    //
    // Parameters:
    //
    // - `assignments`: One `HookFamilyAssignment` per hook.
    //
    if (hookFamilies.length > 0) {
      v4FeePolicy.batchSetHookFamily(hookFamilies);
    } else {
      console.log(
        "Transaction 42 skipped: no hook family rows", Constants.HyperEVM.HOOK_FAMILIES_CSV
      );
    }

    // -----------------------------------------------------------------------------------------
    // Transaction 43
    //
    // Set `V4FeePolicy` stable-stable pair fees for the aggregator hook family, from
    // `STABLE_STABLE_PAIRS_CSV`. Skipped while that list is empty; the numbering holds either way.
    //
    // Parameters:
    //
    // - `assignments`: One `PairClassFeeAssignment` per pair, tokens sorted, family 11, the
    //   stable-stable fee packed into both swap directions.
    //
    if (pairClassFees.length > 0) {
      v4FeePolicy.batchSetPairClassFee(pairClassFees);
    } else {
      console.log(
        "Transaction 43 skipped: no stable-stable pair rows",
        Constants.HyperEVM.STABLE_STABLE_PAIRS_CSV
      );
    }

    // -----------------------------------------------------------------------------------------
    // Transaction 44
    //
    // Transfer `V4FeePolicy` fee-setter permission to `UniswapWormholeMessageReceiver`.
    //
    // Parameters:
    //
    // - `newFeeSetter`: Governance-owned Wormhole message receiver.
    //
    v4FeePolicy.setFeeSetter(Constants.HyperEVM.WORMHOLE_RECEIVER);

    // -----------------------------------------------------------------------------------------
    // Transaction 45
    //
    // Transfer `V4FeePolicy` ownership to `UniswapWormholeMessageReceiver`.
    //
    // Parameters:
    //
    // - `newOwner`: Governance-owned Wormhole message receiver.
    //
    v4FeePolicy.transferOwnership(Constants.HyperEVM.WORMHOLE_RECEIVER);

    // -----------------------------------------------------------------------------------------
    // Transaction 46
    //
    // Transfer `V4FeeAdapter` fee-setter permission to `UniswapWormholeMessageReceiver`.
    //
    // Parameters:
    //
    // - `newFeeSetter`: Governance-owned Wormhole message receiver.
    //
    v4FeeAdapter.setFeeSetter(Constants.HyperEVM.WORMHOLE_RECEIVER);

    // -----------------------------------------------------------------------------------------
    // Transaction 47
    //
    // Transfer `V4FeeAdapter` ownership to `UniswapWormholeMessageReceiver`.
    //
    // Parameters:
    //
    // - `newOwner`: Governance-owned Wormhole message receiver.
    //
    v4FeeAdapter.transferOwnership(Constants.HyperEVM.WORMHOLE_RECEIVER);

    vm.stopBroadcast();

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

  /// @dev Reads the deployment back out of the record.
  function _load() internal {
    uint256 chainId = Constants.HyperEVM.CHAIN_ID;

    syntheticNttUni = SyntheticNttUni(
      recorder.read({chainId: chainId, deploymentName: Constants.Records.SYNTHETIC_NTT_UNI})
    );
    nttManagerImplementation = recorder.read({
      chainId: chainId, deploymentName: Constants.Records.NTT_MANAGER_IMPLEMENTATION
    });
    nttManager = NttManagerNoRateLimiting(
      recorder.read({chainId: chainId, deploymentName: Constants.Records.NTT_MANAGER})
    );
    wormholeTransceiverImplementation = recorder.read({
      chainId: chainId, deploymentName: Constants.Records.WORMHOLE_TRANSCEIVER_IMPLEMENTATION
    });
    wormholeTransceiver = WormholeTransceiver(
      recorder.read({chainId: chainId, deploymentName: Constants.Records.WORMHOLE_TRANSCEIVER})
    );
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

  /// @dev Hook family assignments, read from `HOOK_FAMILIES_CSV`.
  function _hookFamilies() internal view returns (HookFamilyAssignment[] memory) {
    return Lists.hookFamilies(Constants.HyperEVM.HOOK_FAMILIES_CSV);
  }

  /// @dev Stable-stable pairs, read from `STABLE_STABLE_PAIRS_CSV` and turned into the assignments
  /// `batchSetPairClassFee` takes: tokens sorted as the policy requires, aggregator family,
  /// stable-stable fee in both swap directions.
  function _pairClassFees() internal view returns (PairClassFeeAssignment[] memory assignments) {
    Pair[] memory pairs = Lists.stableStablePairs(Constants.HyperEVM.STABLE_STABLE_PAIRS_CSV);
    assignments = new PairClassFeeAssignment[](pairs.length);
    for (uint256 i; i < pairs.length; i++) {
      (address token0, address token1) = _sort(pairs[i].token0, pairs[i].token1);
      assignments[i] = PairClassFeeAssignment({
        currency0: Currency.wrap(token0),
        currency1: Currency.wrap(token1),
        familyId: AGG_HOOK_FAMILY_ID,
        feeValue: _bothDirections(Constants.HyperEVM.STABLE_STABLE_FEE)
      });
    }
  }

  /// @dev Sorts two addresses ascending, the order `V4FeePolicy` requires of a pair.
  function _sort(address a, address b) internal pure returns (address, address) {
    return a < b ? (a, b) : (b, a);
  }

  /// @dev The key `V4FeePolicy` stores a sorted pair under.
  function _pairHash(Currency c0, Currency c1) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(Currency.unwrap(c0), Currency.unwrap(c1)));
  }

  /// @dev Packs one fee into both swap directions of a v4 protocol fee: the lower 12 bits apply
  /// to zero-for-one swaps and the upper 12 bits to one-for-zero.
  function _bothDirections(uint24 fee) internal pure returns (uint24) {
    return fee << 12 | fee;
  }

  /// @dev Asserts the deployment landed in the state the proposal assumes.
  function _check() internal view {
    address receiver = Constants.HyperEVM.WORMHOLE_RECEIVER;
    address poolManager = Constants.HyperEVM.POOL_MANAGER;
    uint16 ethChainId = WormholeChainId.Ethereum;

    FeeBucket[] memory feeBuckets = _feeBuckets();
    HookFamilyAssignment[] memory hookFamilies = _hookFamilies();
    PairClassFeeAssignment[] memory pairClassFees = _pairClassFees();

    // SyntheticNttUni
    require(syntheticNttUni.ntt() == address(nttManager), "syntheticNttUni.ntt");
    require(syntheticNttUni.owner() == receiver, "syntheticNttUni.owner");
    require(syntheticNttUni.decimals() == 18, "syntheticNttUni.decimals");

    // NttManager
    require(
      ERC1967Reader.implementation(address(nttManager)) == nttManagerImplementation,
      "nttManager.implementation"
    );
    require(nttManager.chainId() == Constants.HyperEVM.WORMHOLE_CHAIN_ID, "nttManager.chainId");
    require(nttManager.getMode() == uint8(IManagerBase.Mode.BURNING), "nttManager.mode");
    require(nttManager.token() == address(syntheticNttUni), "nttManager.token");
    require(nttManager.getThreshold() == TRANSCEIVER_THRESHOLD, "nttManager.threshold");
    require(nttManager.owner() == receiver, "nttManager.owner");
    require(nttManager.pauser() == address(0x00), "nttManager.pauser");

    address[] memory enabledTransceivers = nttManager.getTransceivers();

    require(enabledTransceivers.length == 1, "nttManager.transceivers.length");
    require(
      enabledTransceivers[0] == address(wormholeTransceiver), "nttManager.transceivers.address"
    );

    NttManagerNoRateLimiting.TransceiverInfo[] memory transceivers = nttManager.getTransceiverInfo();

    require(transceivers.length == 1, "nttManager.transceiverInfo.length");
    require(transceivers[0].registered, "nttManager.transceiverInfo.registered");
    require(transceivers[0].enabled, "nttManager.transceiverInfo.enabled");
    // Assigned by `setTransceiver`. The threshold-of-1 attestation bitmap keys off this
    // index, so a length of one does not imply the registered transceiver sits at index zero.
    require(transceivers[0].index == 0, "nttManager.transceiverInfo.index");

    NttManagerNoRateLimiting.NttManagerPeer memory peer = nttManager.getPeer(ethChainId);

    require(
      WormholeEncoder.fromWormholeFormat(peer.peerAddress) == uniswap.ethereum.nttManager,
      "nttManager.peer"
    );
    require(peer.tokenDecimals == 18, "nttManager.peer.decimals");

    // WormholeTransceiver
    require(
      ERC1967Reader.implementation(address(wormholeTransceiver))
        == wormholeTransceiverImplementation,
      "wormholeTransceiver.implementation"
    );
    require(
      wormholeTransceiver.nttManager() == address(nttManager), "wormholeTransceiver.nttManager"
    );
    require(
      wormholeTransceiver.nttManagerToken() == address(syntheticNttUni),
      "wormholeTransceiver.nttManagerToken"
    );
    require(
      wormholeTransceiver.consistencyLevel() == CONSISTENCY_LEVEL,
      "wormholeTransceiver.consistencyLevel"
    );
    require(
      wormholeTransceiver.customConsistencyLevel() == 0,
      "wormholeTransceiver.customConsistencyLevel"
    );
    require(wormholeTransceiver.additionalBlocks() == 0, "wormholeTransceiver.additionalBlocks");
    require(
      wormholeTransceiver.customConsistencyLevelAddress() == address(0x00),
      "wormholeTransceiver.customConsistencyLevelAddress"
    );
    require(
      address(wormholeTransceiver.wormhole()) == Constants.HyperEVM.WORMHOLE_CORE,
      "wormholeTransceiver.wormhole"
    );
    require(wormholeTransceiver.owner() == receiver, "wormholeTransceiver.owner");
    require(wormholeTransceiver.pauser() == address(0x00), "wormholeTransceiver.pauser");
    require(
      WormholeEncoder.fromWormholeFormat(wormholeTransceiver.getWormholePeer(ethChainId))
        == uniswap.ethereum.wormholeTransceiver,
      "wormholeTransceiver.peer"
    );

    // TokenJar
    require(tokenJar.releaser() == address(releaser), "tokenJar.releaser");
    require(tokenJar.owner() == receiver, "tokenJar.owner");

    // WormholeReleaser
    require(address(releaser.NTT_MANAGER()) == address(nttManager), "releaser.nttManager");
    require(address(releaser.RESOURCE()) == address(syntheticNttUni), "releaser.resource");
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

    for (uint256 i; i < hookFamilies.length; i++) {
      require(
        v4FeePolicy.hookFamilyId(hookFamilies[i].hook) == hookFamilies[i].familyId,
        "v4FeePolicy.hookFamilyId"
      );
    }

    for (uint256 i; i < pairClassFees.length; i++) {
      PairClassFeeAssignment memory a = pairClassFees[i];
      require(
        v4FeePolicy.pairClassFees(_pairHash(a.currency0, a.currency1), a.familyId) == a.feeValue,
        "v4FeePolicy.pairClassFees"
      );
    }
  }

  /// @dev Writes the deployments for the proposal to read back, then logs them. Runs only after
  /// `_check`, so nothing reaches the record unless it was verified.
  function _record() internal {
    uint256 chainId = Constants.HyperEVM.CHAIN_ID;

    recorder.write({
      chainId: chainId,
      deploymentName: Constants.Records.SYNTHETIC_NTT_UNI,
      deployment: address(syntheticNttUni)
    });
    recorder.write({
      chainId: chainId,
      deploymentName: Constants.Records.NTT_MANAGER_IMPLEMENTATION,
      deployment: nttManagerImplementation
    });
    recorder.write({
      chainId: chainId,
      deploymentName: Constants.Records.NTT_MANAGER,
      deployment: address(nttManager)
    });
    recorder.write({
      chainId: chainId,
      deploymentName: Constants.Records.WORMHOLE_TRANSCEIVER_IMPLEMENTATION,
      deployment: wormholeTransceiverImplementation
    });
    recorder.write({
      chainId: chainId,
      deploymentName: Constants.Records.WORMHOLE_TRANSCEIVER,
      deployment: address(wormholeTransceiver)
    });
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

    console.log("SyntheticNttUni                   :", address(syntheticNttUni));
    console.log("NttManager implementation         :", nttManagerImplementation);
    console.log("NttManager proxy                  :", address(nttManager));
    console.log("WormholeTransceiver implementation:", wormholeTransceiverImplementation);
    console.log("WormholeTransceiver proxy         :", address(wormholeTransceiver));
    console.log("TokenJar                          :", address(tokenJar));
    console.log("WormholeReleaser                  :", address(releaser));
    console.log("V3OpenFeeAdapter                  :", address(v3OpenFeeAdapter));
    console.log("V4FeeAdapter                      :", address(v4FeeAdapter));
    console.log("V4FeePolicy                       :", address(v4FeePolicy));
  }
}
