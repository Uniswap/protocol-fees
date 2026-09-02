// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";

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
import {IWormhole} from "../Interfaces.sol";
import "../Constants.sol" as Constants;

/// @dev Consistency level 202 is what Wormhole's own deployment scripts use; the three
/// custom-consistency parameters are only read when the level is 203.
uint8 constant CONSISTENCY_LEVEL = 202;

/// @dev Number of transceivers that must attest to a message before the manager executes it.
/// Registering the first transceiver raises it from 0 to 1, and the manager rejects any value
/// above the number of enabled transceivers, so with one transceiver 1 is the only value it can
/// hold. Never set explicitly; asserted by `_check`.
uint8 constant TRANSCEIVER_THRESHOLD = 1;

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
// unset again, which should happen only after both prerequisite scripts have run.
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
// Proposal 4 split this work across two scripts per chain, deploy and then configure, because BNB
// Chain, Polygon, and Ethereum all had to be brought up against one another and the peer addresses
// were not known until every chain had been deployed. Nothing is deployed on the Ethereum side
// this time, so the peers are known up front and the two halves collapse into a single run.
//
// ---
//
// `run` asserts the resulting state in its own simulation before it records anything. To apply
// the same assertions to the live chain afterwards, from the record alone:
//
// forge script script/proposal-7/prereq/DeployWormholeInfraHyperEVM.s.sol --sig "check()"
// --rpc-url hyperevm
//
contract DeployWormholeInfraHyperEVM is Script {
  Recorder internal recorder;
  Uniswap internal uniswap;

  SyntheticNttUni internal syntheticNttUni;

  address internal nttManagerImplementation;
  NttManagerNoRateLimiting internal nttManager;

  address internal wormholeTransceiverImplementation;
  WormholeTransceiver internal wormholeTransceiver;

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
  }

  /// @dev Asserts the deployment landed in the state the proposal assumes.
  function _check() internal view {
    address receiver = Constants.HyperEVM.WORMHOLE_RECEIVER;
    uint16 ethChainId = WormholeChainId.Ethereum;

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
  }

  /// @dev Writes the deployments for the fee infra script and the proposal to read back, then
  /// logs them. Runs only after `_check`, so nothing reaches the record unless it was verified.
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

    console.log("SyntheticNttUni                   :", address(syntheticNttUni));
    console.log("NttManager implementation         :", nttManagerImplementation);
    console.log("NttManager proxy                  :", address(nttManager));
    console.log("WormholeTransceiver implementation:", wormholeTransceiverImplementation);
    console.log("WormholeTransceiver proxy         :", address(wormholeTransceiver));
  }
}
