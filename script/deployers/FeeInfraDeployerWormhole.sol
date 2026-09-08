// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {IManagerBase} from "lib/native-token-transfers/evm/src/interfaces/IManagerBase.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {SyntheticNttUni} from "../../src/wormhole/SyntheticNttUni.sol";
import {WormholeReleaser} from "../../src/releasers/WormholeReleaser.sol";
import {IReleaser} from "../../src/interfaces/IReleaser.sol";
import {IWormhole} from "../proposal-7/Interfaces.sol";
import {FeeInfraParams, WormholeInfraParams} from "../shared/FeeInfraParams.sol";
import {FeeInfraDeployer} from "./FeeInfraDeployer.sol";

/// @dev Creation code of the two Wormhole contracts, without constructor arguments.
///
/// The code comes in as an argument rather than being compiled into this contract because the two
/// implementations are about 35KB of creation code between them, which would put this deployer's
/// initcode over the EIP-3860 limit of 48KB. The script supplies compiled code and nothing else:
/// this contract appends every constructor argument itself, so no value reaches a Wormhole
/// contract that is not visible in this source.
///
/// The code must already have the `TransceiverStructs` library linked. Forge does that when the
/// script takes `type(...).creationCode`, deploying the library as the transaction before this
/// one.
struct WormholeCreationCode {
  /// @dev `NttManagerNoRateLimiting`.
  bytes nttManager;
  /// @dev `WormholeTransceiver`.
  bytes wormholeTransceiver;
}

/// @dev The calls this deployer makes on the two proxies, named here rather than imported from
/// the implementations so their creation code stays out of this contract's bytecode.
interface INttManagerSetup {
  function initialize() external;
  function setTransceiver(address transceiver) external;
  function setPeer(uint16 peerChainId, bytes32 peerContract, uint8 decimals, uint256 inboundLimit)
    external;
  function transferOwnership(address newOwner) external;
  function transferPauserCapability(address newPauser) external;
}

interface IWormholeTransceiverSetup {
  function initialize() external payable;
  function setWormholePeer(uint16 peerChainId, bytes32 peerContract) external payable;
  function transferPauserCapability(address newPauser) external;
}

// -------------------------------------------------------------------------------------------------
// `FeeInfraDeployer` for a chain whose UNI arrives over Wormhole. The constructor deploys synthetic
// UNI, the NTT manager and transceiver behind their proxies, registers Ethereum as the peer of
// both, and hands them to the governance receiver, then runs the fee infra with a releaser that
// burns synthetic UNI through the manager. One transaction for all of it.
//
// Payable because the transceiver's initializer and the peer registration each publish a Wormhole
// message. The script must fund the deployment with exactly twice the message fee, which it
// queries the same way the constructor does; nothing is refunded, so nothing is held.
//
// Steps are labelled `W.00` onward, the Wormhole phase of a deployment. W.00, the
// `TransceiverStructs` library, is the transaction before this one.
//
contract FeeInfraDeployerWormhole is FeeInfraDeployer {
  bytes32 constant SALT_SYNTHETIC_NTT_UNI = bytes32(uint256(11));
  bytes32 constant SALT_NTT_MANAGER_IMPLEMENTATION = bytes32(uint256(12));
  bytes32 constant SALT_NTT_MANAGER = bytes32(uint256(13));
  bytes32 constant SALT_WORMHOLE_TRANSCEIVER_IMPLEMENTATION = bytes32(uint256(14));
  bytes32 constant SALT_WORMHOLE_TRANSCEIVER = bytes32(uint256(15));

  /// @dev UNI has 18 decimals on Ethereum, and the manager needs to know its peer's.
  uint8 constant ETHEREUM_UNI_DECIMALS = 18;

  SyntheticNttUni public syntheticNttUni;
  address public nttManagerImplementation;
  address public nttManager;
  address public wormholeTransceiverImplementation;
  address public wormholeTransceiver;

  constructor(
    WormholeInfraParams memory w,
    FeeInfraParams memory f,
    WormholeCreationCode memory code
  ) payable {
    require(msg.value == 2 * IWormhole(w.wormholeCore).messageFee(), "value != 2 * messageFee");
    _deployWormholeInfra(w, code);
    _deployFeeInfra(f);
  }

  /// @dev Steps W.01 through W.15.
  function _deployWormholeInfra(WormholeInfraParams memory w, WormholeCreationCode memory code)
    internal
  {
    // -----------------------------------------------------------------------------------------
    // W.01
    //
    // Deploy `SyntheticNttUni`.
    //
    syntheticNttUni = new SyntheticNttUni{salt: SALT_SYNTHETIC_NTT_UNI}();

    // -----------------------------------------------------------------------------------------
    // W.02
    //
    // Deploy `NttManager` implementation with no rate limiting, from the passed creation code
    // plus the constructor arguments appended here.
    //
    // Parameters:
    //
    // - `_token`: This chain's deployment of UNI (`SyntheticNttUni`).
    // - `_mode`: `BURNING` for all foreign chains.
    // - `_chainId`: Wormhole-defined chain ID, not EIP155-defined.
    //
    nttManagerImplementation = _create2(
      abi.encodePacked(
        code.nttManager,
        abi.encode(address(syntheticNttUni), IManagerBase.Mode.BURNING, w.wormholeChainId)
      ),
      SALT_NTT_MANAGER_IMPLEMENTATION
    );

    // -----------------------------------------------------------------------------------------
    // W.03
    //
    // Deploy `NttManager` proxy and set its implementation.
    //
    // We generally avoid using proxy-implementation pairs. Since Wormhole has only defined a
    // collection of NttManager systems as proxy implementations, though, it will be best to use
    // their code and simply avoid any potential mishaps on our end.
    //
    // Steps W.12 through W.15 transfer the full authority to the governance receiver contract to
    // mitigate upgrade authority risk.
    //
    // Parameters:
    //
    // - `implementation`: Implementation contract address.
    // - `_data`: Optional call to make during deployment. We dont use this.
    //
    nttManager = address(
      new ERC1967Proxy{salt: SALT_NTT_MANAGER}({
        implementation: nttManagerImplementation, _data: new bytes(0)
      })
    );

    // -----------------------------------------------------------------------------------------
    // W.04
    //
    // Initialize `NttManager` proxy. This deployer becomes its owner and pauser.
    //
    INttManagerSetup(nttManager).initialize();

    // -----------------------------------------------------------------------------------------
    // W.05
    //
    // Deploy `WormholeTransceiver` implementation, from the passed creation code plus the
    // constructor arguments appended here.
    //
    // The transceiver is the messaging layer and the manager is the token layer, but the
    // transceiver takes the manager as a constructor argument, so it must be deployed second.
    //
    // Parameters:
    //
    // - `nttManager`: NttManager proxy address.
    // - `wormholeCoreBridge`: This chain's Wormhole core bridge.
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
    wormholeTransceiverImplementation = _create2(
      abi.encodePacked(
        code.wormholeTransceiver,
        abi.encode(
          nttManager, w.wormholeCore, w.consistencyLevel, uint8(0), uint16(0), address(0x00)
        )
      ),
      SALT_WORMHOLE_TRANSCEIVER_IMPLEMENTATION
    );

    // -----------------------------------------------------------------------------------------
    // W.06
    //
    // Deploy `WormholeTransceiver` proxy.
    //
    wormholeTransceiver = address(
      new ERC1967Proxy{salt: SALT_WORMHOLE_TRANSCEIVER}({
        implementation: wormholeTransceiverImplementation, _data: new bytes(0)
      })
    );

    // -----------------------------------------------------------------------------------------
    // W.07
    //
    // Initialize `WormholeTransceiver` proxy with one message fee, for the call to
    // `wormhole.publishMessage` in the initializer. This deployer becomes its owner and pauser.
    //
    uint256 messageFee = IWormhole(w.wormholeCore).messageFee();
    IWormholeTransceiverSetup(wormholeTransceiver).initialize{value: messageFee}();

    // -----------------------------------------------------------------------------------------
    // W.08
    //
    // Set `NttManager` proxy's transceiver to the `WormholeTransceiver` proxy. Registering the
    // first transceiver also raises the attestation threshold from 0 to 1, and the manager
    // rejects any value above the number of enabled transceivers, so with one transceiver 1 is
    // the only value it can hold. Never set explicitly; the script asserts it.
    //
    INttManagerSetup(nttManager).setTransceiver({transceiver: wormholeTransceiver});

    // -----------------------------------------------------------------------------------------
    // W.09
    //
    // Set `SyntheticNttUni` mint authority to `NttManager` proxy.
    //
    syntheticNttUni.setNtt({newNtt: nttManager});

    // -----------------------------------------------------------------------------------------
    // W.10
    //
    // Set Ethereum `WormholeTransceiver` proxy as a peer on the Ethereum Chain Id, with one
    // message fee.
    //
    // The Ethereum contracts already exist and are owned by the Timelock, so the matching
    // registration in the other direction is the governance half of the proposal.
    //
    IWormholeTransceiverSetup(wormholeTransceiver).setWormholePeer{value: messageFee}({
      peerChainId: w.ethereumWormholeChainId,
      peerContract: _toWormholeFormat(w.ethereumWormholeTransceiver)
    });

    // -----------------------------------------------------------------------------------------
    // W.11
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
    INttManagerSetup(nttManager).setPeer({
      peerChainId: w.ethereumWormholeChainId,
      peerContract: _toWormholeFormat(w.ethereumNttManager),
      decimals: ETHEREUM_UNI_DECIMALS,
      inboundLimit: 0
    });

    // -----------------------------------------------------------------------------------------
    // W.12
    //
    // Transfer ownership of `SyntheticNttUni` to governance.
    //
    syntheticNttUni.transferOwnership({newOwner: w.receiver});

    // -----------------------------------------------------------------------------------------
    // W.13
    //
    // Transfer `NttManager` proxy ownership to `UniswapWormholeMessageReceiver`. This call also
    // iterates registered transceivers and forwards the ownership transfer to each via
    // `transferTransceiverOwnership` (`onlyNttManager`), so the `WormholeTransceiver` proxy ends
    // up owned by the same address without an explicit second transfer.
    //
    INttManagerSetup(nttManager).transferOwnership({newOwner: w.receiver});

    // -----------------------------------------------------------------------------------------
    // W.14
    //
    // Renounce pauser capability on the `WormholeTransceiver` proxy.
    //
    // This deployer is set as the pauser during proxy initialization and is independent of
    // ownership. Even after ownership transfer, the deployer remains the pauser unless the
    // capability is transferred (or renounced). We renounce by setting the pauser to the zero
    // address so no party can pause the transceiver going forward.
    //
    IWormholeTransceiverSetup(wormholeTransceiver).transferPauserCapability({newPauser: address(0)});

    // -----------------------------------------------------------------------------------------
    // W.15
    //
    // Renounce pauser capability on the `NttManager` proxy. Same rationale as the transceiver.
    //
    INttManagerSetup(nttManager).transferPauserCapability({newPauser: address(0)});
  }

  /// @dev F.01: the releaser that burns synthetic UNI through the manager deployed above.
  ///
  /// Parameters:
  ///
  /// - `_nttManager`: This chain's NttManager proxy.
  /// - `_resource`: This chain's SyntheticNttUni.
  /// - `_threshold`: Minimum amount of `SyntheticNttUni` required to release.
  /// - `_tokenJar`: `TokenJar`.
  function _deployReleaser(address _tokenJar, uint256 _threshold)
    internal
    override
    returns (IReleaser)
  {
    return new WormholeReleaser{salt: SALT_RELEASER}({
      _nttManager: nttManager,
      _resource: address(syntheticNttUni),
      _threshold: _threshold,
      _tokenJar: _tokenJar
    });
  }

  /// @dev CREATE2 from initcode held in memory, for contracts whose code arrives as an argument.
  function _create2(bytes memory initcode, bytes32 salt) internal returns (address deployed) {
    assembly ("memory-safe") {
      deployed := create2(0, add(initcode, 32), mload(initcode), salt)
    }
    require(deployed != address(0), "create2");
  }

  /// @dev Wormhole's 32-byte form of an EVM address: left-padded with zeros.
  function _toWormholeFormat(address addr) internal pure returns (bytes32) {
    return bytes32(uint256(uint160(addr)));
  }
}
