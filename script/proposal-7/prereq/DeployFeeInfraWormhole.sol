// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {console} from "forge-std/Script.sol";

import {
  NttManagerNoRateLimiting
} from "lib/native-token-transfers/evm/src/NttManager/NttManagerNoRateLimiting.sol";
import {IManagerBase} from "lib/native-token-transfers/evm/src/interfaces/IManagerBase.sol";
import {
  WormholeTransceiver
} from "lib/native-token-transfers/evm/src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {SyntheticNttUni} from "../../../src/wormhole/SyntheticNttUni.sol";
import {WormholeReleaser} from "../../../src/releasers/WormholeReleaser.sol";
import {IReleaser} from "../../../src/interfaces/IReleaser.sol";
import {WormholeEncoder} from "govkit/bridges/WormholeEncoder.sol";
import {WormholeInfraParams} from "../../shared/FeeInfraParams.sol";
import {WormholeInfraChecks, WormholeInfraAddresses} from "../../shared/WormholeInfraChecks.sol";
import {IWormhole} from "../Interfaces.sol";
import {Records} from "../params/Constants.sol";
import {DeployFeeInfra} from "./DeployFeeInfra.sol";

// -------------------------------------------------------------------------------------------------
// `DeployFeeInfra` for a chain whose UNI arrives over Wormhole: adds synthetic UNI, the NTT
// manager and transceiver behind their proxies, peer registration with Ethereum, and handover to
// the governance receiver, all before the fee phase, and supplies the releaser that burns
// synthetic UNI through the manager.
//
// Transactions are numbered `W.00` onward, the Wormhole phase of a deployment.
//
abstract contract DeployFeeInfraWormhole is DeployFeeInfra {
  /// @dev The chain's Wormhole infra parameters, built by the chain script.
  function _wormholeParams() internal view virtual returns (WormholeInfraParams memory);

  SyntheticNttUni internal syntheticNttUni;

  address internal nttManagerImplementation;
  NttManagerNoRateLimiting internal nttManager;

  address internal wormholeTransceiverImplementation;
  WormholeTransceiver internal wormholeTransceiver;

  WormholeReleaser internal wormholeReleaser;

  /// @dev The Wormhole phase, then the fee phase. The order is forced: the releaser the fee phase
  /// asks for is built from the manager and token deployed here.
  function _deploy() internal override {
    _deployWormholeInfra();
    _deployFeeInfra();
  }

  function _load() internal override {
    _loadWormholeInfra();
    _loadFeeInfra();
  }

  function _check() internal view override {
    _checkWormholeInfra();
    _checkFeeInfra();
  }

  function _record() internal override {
    _recordWormholeInfra();
    _recordFeeInfra();
  }

  /// @dev Transactions W.00 through W.15.
  function _deployWormholeInfra() internal {
    WormholeInfraParams memory p = _wormholeParams();

    // -----------------------------------------------------------------------------------------
    // Transaction W.00
    //
    // (Implicit) Deploy the `TransceiverStructs` external library for wormhole contracts.

    // -----------------------------------------------------------------------------------------
    // Transaction W.01
    //
    // Deploy `SyntheticNttUni`.
    //
    syntheticNttUni = new SyntheticNttUni();

    // -----------------------------------------------------------------------------------------
    // Transaction W.02
    //
    // Deploy `NttManager` implementation with no rate limiting.
    //
    // Parameters:
    //
    // - `_token`: This chain's deployment of UNI (`SyntheticNttUni`).
    // - `_mode`: `BURNING` for all foreign chains.
    // - `_chainId`: Wormhole-defined chain ID, not EIP155-defined.
    //
    nttManagerImplementation = address(
      new NttManagerNoRateLimiting({
        _token: address(syntheticNttUni),
        _mode: IManagerBase.Mode.BURNING,
        _chainId: p.wormholeChainId
      })
    );

    // -----------------------------------------------------------------------------------------
    // Transaction W.03
    //
    // Deploy `NttManager` proxy and set its implementation.
    //
    // We generally avoid using proxy-implementation pairs. Since Wormhole has only defined a
    // collection of NttManager systems as proxy implementations, though, it will be best to use
    // their code and simply avoid any potential mishaps on our end.
    //
    // Transactions W.12 through W.15 transfer the full authority to the governance receiver
    // contract to mitigate upgrade authority risk.
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
    // Transaction W.04
    //
    // Initialize `NttManager` proxy.
    //
    nttManager.initialize();

    // -----------------------------------------------------------------------------------------
    // Transaction W.05
    //
    // Deploy `WormholeTransceiver` implementation.
    //
    // The transceiver is the messaging layer and the manager is the token layer, but the
    // transceiver takes the manager as a constructor argument, so it must be deployed second.
    //
    // Parameters:
    //
    // - `nttManager`: NttManager proxy address.
    // - `wormholeCoreBridge`: This chain's Wormhole core bridge.
    // - `_consistencyLevel`: 202, per Wormhole documentation [1].
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
        wormholeCoreBridge: p.wormholeCore,
        _consistencyLevel: p.consistencyLevel,
        _customConsistencyLevel: 0,
        _additionalBlocks: 0,
        _customConsistencyLevelAddress: address(0x00)
      })
    );

    // -----------------------------------------------------------------------------------------
    // Transaction W.06
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
    uint256 messageFee = IWormhole(p.wormholeCore).messageFee();

    // -----------------------------------------------------------------------------------------
    // Transaction W.07
    //
    // Initialize `WormholeTransceiver` proxy with a recently queried `messageFee`.
    //
    // Parameters:
    //
    // - `value`: Call value for a call to `wormhole.publishMessage` in the initializer.
    //
    wormholeTransceiver.initialize{value: messageFee}();

    // -----------------------------------------------------------------------------------------
    // Transaction W.08
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
    // Transaction W.09
    //
    // Set `SyntheticNttUni` mint authority to `NttManager` proxy.
    //
    // Parameters:
    //
    // - `newNtt`: NttManager proxy.
    //
    syntheticNttUni.setNtt({newNtt: address(nttManager)});

    // -----------------------------------------------------------------------------------------
    // Transaction W.10
    //
    // Set Ethereum `WormholeTransceiver` proxy as a peer on the Ethereum Chain Id.
    //
    // The Ethereum contracts already exist and are owned by the Timelock, so the matching
    // registration in the other direction is the governance half of the proposal.
    //
    // Parameters:
    //
    // - `peerChainId`: Wormhole-defined Ethereum Chain Id.
    // - `peerContract`: Ethereum WormholeTransceiver proxy.
    //
    wormholeTransceiver.setWormholePeer{value: messageFee}({
      peerChainId: p.ethereumWormholeChainId,
      peerContract: WormholeEncoder.toWormholeFormat(p.ethereumWormholeTransceiver)
    });

    // -----------------------------------------------------------------------------------------
    // Transaction W.11
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
      peerChainId: p.ethereumWormholeChainId,
      peerContract: WormholeEncoder.toWormholeFormat(p.ethereumNttManager),
      decimals: 18,
      inboundLimit: 0
    });

    // -----------------------------------------------------------------------------------------
    // Transaction W.12
    //
    // Transfer ownership of `SyntheticNttUni` to governance.
    //
    // Parameters:
    //
    // - `newOwner`: Governance-owned Wormhole message receiver.
    //
    syntheticNttUni.transferOwnership({newOwner: p.receiver});

    // -----------------------------------------------------------------------------------------
    // Transaction W.13
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
    nttManager.transferOwnership({newOwner: p.receiver});

    // -----------------------------------------------------------------------------------------
    // Transaction W.14
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
    // Transaction W.15
    //
    // Renounce pauser capability on the `NttManager` proxy. Same rationale as the transceiver.
    //
    // Parameters:
    //
    // - `newPauser`: Zero address, renouncing the capability.
    //
    nttManager.transferPauserCapability(address(0));
  }

  /// @dev The fee phase's releaser hook, transaction F.01. On a Wormhole chain the releaser burns
  /// synthetic UNI through the NTT manager, so it is built from the Wormhole phase's deployments
  /// plus the two values the fee phase passes in: its `TokenJar`, and the minimum amount of
  /// synthetic UNI required to release.
  function _deployReleaser(address _tokenJar, uint256 _threshold)
    internal
    override
    returns (IReleaser)
  {
    wormholeReleaser = new WormholeReleaser({
      _nttManager: address(nttManager),
      _resource: address(syntheticNttUni),
      _threshold: _threshold,
      _tokenJar: _tokenJar
    });
    return wormholeReleaser;
  }

  /// @dev Reads the Wormhole phase's deployments back out of the record.
  function _loadWormholeInfra() internal {
    uint256 chainId = block.chainid;

    syntheticNttUni =
      SyntheticNttUni(recorder.read({chainId: chainId, deploymentName: Records.SYNTHETIC_NTT_UNI}));
    nttManagerImplementation =
      recorder.read({chainId: chainId, deploymentName: Records.NTT_MANAGER_IMPLEMENTATION});
    nttManager = NttManagerNoRateLimiting(
      recorder.read({chainId: chainId, deploymentName: Records.NTT_MANAGER})
    );
    wormholeTransceiverImplementation = recorder.read({
      chainId: chainId, deploymentName: Records.WORMHOLE_TRANSCEIVER_IMPLEMENTATION
    });
    wormholeTransceiver = WormholeTransceiver(
      recorder.read({chainId: chainId, deploymentName: Records.WORMHOLE_TRANSCEIVER})
    );
    wormholeReleaser = WormholeReleaser(
      payable(recorder.read({chainId: chainId, deploymentName: Records.RELEASER}))
    );
  }

  /// @dev Asserts the Wormhole phase's deployments landed in the state `_wormholeParams` asks
  /// for, plus the Wormhole-specific wiring of the releaser the hook built.
  function _checkWormholeInfra() internal view {
    WormholeInfraChecks.check(_wormholeInfraAddresses(), _wormholeParams());
  }

  function _wormholeInfraAddresses() internal view returns (WormholeInfraAddresses memory) {
    return WormholeInfraAddresses({
      syntheticNttUni: syntheticNttUni,
      nttManagerImplementation: nttManagerImplementation,
      nttManager: nttManager,
      wormholeTransceiverImplementation: wormholeTransceiverImplementation,
      wormholeTransceiver: wormholeTransceiver,
      releaser: wormholeReleaser
    });
  }

  /// @dev Writes the Wormhole phase's deployments to the record, then logs them.
  function _recordWormholeInfra() internal {
    uint256 chainId = block.chainid;

    recorder.write({
      chainId: chainId,
      deploymentName: Records.SYNTHETIC_NTT_UNI,
      deployment: address(syntheticNttUni)
    });
    recorder.write({
      chainId: chainId,
      deploymentName: Records.NTT_MANAGER_IMPLEMENTATION,
      deployment: nttManagerImplementation
    });
    recorder.write({
      chainId: chainId, deploymentName: Records.NTT_MANAGER, deployment: address(nttManager)
    });
    recorder.write({
      chainId: chainId,
      deploymentName: Records.WORMHOLE_TRANSCEIVER_IMPLEMENTATION,
      deployment: wormholeTransceiverImplementation
    });
    recorder.write({
      chainId: chainId,
      deploymentName: Records.WORMHOLE_TRANSCEIVER,
      deployment: address(wormholeTransceiver)
    });

    console.log("SyntheticNttUni                   :", address(syntheticNttUni));
    console.log("NttManager implementation         :", nttManagerImplementation);
    console.log("NttManager proxy                  :", address(nttManager));
    console.log("WormholeTransceiver implementation:", wormholeTransceiverImplementation);
    console.log("WormholeTransceiver proxy         :", address(wormholeTransceiver));
  }
}
