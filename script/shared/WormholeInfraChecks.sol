// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {ERC1967Reader} from "govkit/forge/ERC1967Reader.sol";
import {WormholeEncoder} from "govkit/bridges/WormholeEncoder.sol";

import {
  NttManagerNoRateLimiting
} from "lib/native-token-transfers/evm/src/NttManager/NttManagerNoRateLimiting.sol";
import {IManagerBase} from "lib/native-token-transfers/evm/src/interfaces/IManagerBase.sol";
import {
  WormholeTransceiver
} from "lib/native-token-transfers/evm/src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";

import {SyntheticNttUni} from "../../src/wormhole/SyntheticNttUni.sol";
import {WormholeReleaser} from "../../src/releasers/WormholeReleaser.sol";
import {WormholeInfraParams} from "./FeeInfraParams.sol";

/// @dev What a Wormhole infra deployment produced, however it was deployed, plus the releaser
/// the fee infra was given, whose Wormhole wiring is checked here.
struct WormholeInfraAddresses {
  SyntheticNttUni syntheticNttUni;
  address nttManagerImplementation;
  NttManagerNoRateLimiting nttManager;
  address wormholeTransceiverImplementation;
  WormholeTransceiver wormholeTransceiver;
  WormholeReleaser releaser;
}

/// @dev Asserts that a Wormhole infra deployment matches the params it was given. The struct
/// that drove the deployment is the oracle for the check, so the two cannot drift, and the check
/// does not care whether a script or a deployer contract did the deploying.
///
/// Every assertion names the field it checks, so a failure reads as the field that is wrong.
library WormholeInfraChecks {
  /// @dev Number of transceivers that must attest to a message before the manager executes it.
  /// Registering the first transceiver raises it from 0 to 1, and the manager rejects any value
  /// above the number of enabled transceivers, so with one transceiver 1 is the only value it can
  /// hold. Never set explicitly; asserted here.
  uint8 constant TRANSCEIVER_THRESHOLD = 1;

  /// @dev UNI has 18 decimals on Ethereum, and synthetic UNI matches.
  uint8 constant UNI_DECIMALS = 18;

  function check(WormholeInfraAddresses memory a, WormholeInfraParams memory p) internal view {
    // SyntheticNttUni
    require(a.syntheticNttUni.ntt() == address(a.nttManager), "syntheticNttUni.ntt");
    require(a.syntheticNttUni.owner() == p.receiver, "syntheticNttUni.owner");
    require(a.syntheticNttUni.decimals() == UNI_DECIMALS, "syntheticNttUni.decimals");

    // NttManager
    require(
      ERC1967Reader.implementation(address(a.nttManager)) == a.nttManagerImplementation,
      "nttManager.implementation"
    );
    require(a.nttManager.chainId() == p.wormholeChainId, "nttManager.chainId");
    require(a.nttManager.getMode() == uint8(IManagerBase.Mode.BURNING), "nttManager.mode");
    require(a.nttManager.token() == address(a.syntheticNttUni), "nttManager.token");
    require(a.nttManager.getThreshold() == TRANSCEIVER_THRESHOLD, "nttManager.threshold");
    require(a.nttManager.owner() == p.receiver, "nttManager.owner");
    require(a.nttManager.pauser() == address(0x00), "nttManager.pauser");

    address[] memory enabledTransceivers = a.nttManager.getTransceivers();

    require(enabledTransceivers.length == 1, "nttManager.transceivers.length");
    require(
      enabledTransceivers[0] == address(a.wormholeTransceiver), "nttManager.transceivers.address"
    );

    NttManagerNoRateLimiting.TransceiverInfo[] memory transceivers =
      a.nttManager.getTransceiverInfo();

    require(transceivers.length == 1, "nttManager.transceiverInfo.length");
    require(transceivers[0].registered, "nttManager.transceiverInfo.registered");
    require(transceivers[0].enabled, "nttManager.transceiverInfo.enabled");
    // Assigned by `setTransceiver`. The threshold-of-1 attestation bitmap keys off this
    // index, so a length of one does not imply the registered transceiver sits at index zero.
    require(transceivers[0].index == 0, "nttManager.transceiverInfo.index");

    NttManagerNoRateLimiting.NttManagerPeer memory peer =
      a.nttManager.getPeer(p.ethereumWormholeChainId);

    require(
      WormholeEncoder.fromWormholeFormat(peer.peerAddress) == p.ethereumNttManager,
      "nttManager.peer"
    );
    require(peer.tokenDecimals == UNI_DECIMALS, "nttManager.peer.decimals");

    // WormholeTransceiver
    require(
      ERC1967Reader.implementation(address(a.wormholeTransceiver))
        == a.wormholeTransceiverImplementation,
      "wormholeTransceiver.implementation"
    );
    require(
      a.wormholeTransceiver.nttManager() == address(a.nttManager), "wormholeTransceiver.nttManager"
    );
    require(
      a.wormholeTransceiver.nttManagerToken() == address(a.syntheticNttUni),
      "wormholeTransceiver.nttManagerToken"
    );
    require(
      a.wormholeTransceiver.consistencyLevel() == p.consistencyLevel,
      "wormholeTransceiver.consistencyLevel"
    );
    require(
      a.wormholeTransceiver.customConsistencyLevel() == 0,
      "wormholeTransceiver.customConsistencyLevel"
    );
    require(a.wormholeTransceiver.additionalBlocks() == 0, "wormholeTransceiver.additionalBlocks");
    require(
      a.wormholeTransceiver.customConsistencyLevelAddress() == address(0x00),
      "wormholeTransceiver.customConsistencyLevelAddress"
    );
    require(
      address(a.wormholeTransceiver.wormhole()) == p.wormholeCore, "wormholeTransceiver.wormhole"
    );
    require(a.wormholeTransceiver.owner() == p.receiver, "wormholeTransceiver.owner");
    require(a.wormholeTransceiver.pauser() == address(0x00), "wormholeTransceiver.pauser");
    require(
      WormholeEncoder.fromWormholeFormat(
        a.wormholeTransceiver.getWormholePeer(p.ethereumWormholeChainId)
      ) == p.ethereumWormholeTransceiver,
      "wormholeTransceiver.peer"
    );

    // WormholeReleaser, the parts only a Wormhole releaser has. `FeeInfraChecks` checks the rest.
    require(address(a.releaser.NTT_MANAGER()) == address(a.nttManager), "releaser.nttManager");
    require(address(a.releaser.RESOURCE()) == address(a.syntheticNttUni), "releaser.resource");
  }
}
