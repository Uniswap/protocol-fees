// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import "../Constants.sol" as Constants;
import {IWormhole} from "../Interfaces.sol";
import {SyntheticNttUni} from "../../../src/wormhole/SyntheticNttUni.sol";

import {NttManagerNoRateLimiting} from "lib/native-token-transfers/evm/src/NttManager/NttManagerNoRateLimiting.sol";
import {IManagerBase} from "lib/native-token-transfers/evm/src/interfaces/IManagerBase.sol";
import {WormholeTransceiver} from "lib/native-token-transfers/evm/src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// -------------------------------------------------------------------------------------------------
// NOTICE:
//
// This configuration script depends on the following:
//
// 1. `script/proposal-4/deploys/DeployWormholeInfraPolygon.s.sol:DeployWormholeInfraPolygonScript`
// 2. `script/proposal-4/deploys/DeployWormholeInfraEthereum.s.sol:DeployWormholeInfraEthereumScript`
//
// The output of those runs are written by Foundry into the following file path. If the latest is
// incorrect and we need to use it against another deployment, change this path:
string constant POLYGON_DEPLOY_PATH = "broadcast/DeployWormholeInfraPolygon.s.sol/137/run-latest.json";
string constant ETH_DEPLOY_PATH = "broadcast/DeployWormholeInfraEthereum.s.sol/1/run-latest.json";

/// @dev Deployment script outputs.
struct Deployment {
    // On Polygon, this is SyntheticNttUni.
    // On Ethereum, this is the canonical UNI.
    address uni;
    address nttManagerImplementation;
    address nttManagerProxy;
    address wormholeTransceiverImplementation;
    address wormholeTransceiverProxy;
}

contract ConfigWormholeInfraPolygonScript is Script {
    Deployment polygon;
    Deployment eth;

    function run() public {
        Constants.smokeCheck();

        // loads json files of Polygon and ETH deployments and stores them locally in this script.
        loadDeployments();

        vm.startBroadcast();

        // -----------------------------------------------------------------------------------------
        // Query for Wormhole Message Fee.
        //
        uint256 messageFee = IWormhole(Constants.Polygon.WORMHOLE).messageFee();

        // -----------------------------------------------------------------------------------------
        // Transaction 00
        //
        // Set Ethereum WormholeTransceiver proxy as a peer on the Ethereum Chain Id.
        //
        // Parameters:
        //
        // - `peerChainId`: Wormhole-defined Ethereum Chain Id.
        // - `peerContract`: Ethereum WormholeTransceiver proxy.
        //
        WormholeTransceiver(polygon.wormholeTransceiverProxy).setWormholePeer{value: messageFee}({
            peerChainId: Constants.Wormhole.ETH_CHAIN_ID,
            peerContract: bytes32(uint256(uint160(eth.wormholeTransceiverProxy)))
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 01
        //
        // Set the NttManager Proxy on Ethereum as a peer.
        //
        // Parameters:
        //
        // - `peerChainId`: Womrhole-defined Ethereum Chain Id.
        // - `peerContract: Ethereum NttManager proxy.
        // - `decimals`: UNI decimals on Ethereum.
        // - `inboundLimit`: Set to zero when rate limiter is disabled [1].
        //
        // Sources:
        //
        // [1] https://github.com/wormhole-foundation/native-token-transfers/blob/main/evm/README.md
        NttManagerNoRateLimiting(polygon.nttManagerProxy).setPeer({
            peerChainId: Constants.Wormhole.ETH_CHAIN_ID,
            peerContract: bytes32(uint256(uint160(eth.nttManagerProxy))),
            decimals: 18,
            inboundLimit: 0
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 02
        //
        // Transfer NttManager proxy ownership to the Polygon governance receiver. This call also
        // iterates registered transceivers and forwards the ownership transfer to each via
        // `transferTransceiverOwnership` (`onlyNttManager`), so the WormholeTransceiver proxy ends
        // up owned by the same address without an explicit second transfer.
        //
        // Parameters:
        //
        // - `newOwner`: Polygon governance receiver.
        //
        NttManagerNoRateLimiting(polygon.nttManagerProxy).transferOwnership({
            newOwner: Constants.Polygon.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 03
        //
        // Renounce pauser capability on the NttManager proxy.
        //
        // The deployer is set as the pauser when the proxy is initialized in the deploy script and
        // is independent of ownership. We deliberately defer the renounce until after the ownership
        // transfer above so that the renounce lives alongside the rest of the authority handoff in
        // this configuration script. The deployer is still the pauser at this point, so
        // `transferPauserCapability` succeeds under `onlyOwnerOrPauser`.
        //
        NttManagerNoRateLimiting(polygon.nttManagerProxy).transferPauserCapability(address(0));

        // Query Peer data for checks
        //
        address transceiverPeer = address(uint160(uint256(WormholeTransceiver(polygon.wormholeTransceiverProxy).getWormholePeer(Constants.Wormhole.ETH_CHAIN_ID))));

        NttManagerNoRateLimiting.NttManagerPeer memory nttManagerPeer =
            NttManagerNoRateLimiting(polygon.nttManagerProxy).getPeer(Constants.Wormhole.ETH_CHAIN_ID);

        // -----------------------------------------------------------------------------------------
        // Logs
        //
        console2.log("-- VISUALIZED ASSERTIONS -----------------------------");
        console2.log("\n");

        console2.log("polygon.wormholeTransceiverProxy.getWormholePeer()  : ",  transceiverPeer);
        console2.log("eth.wormholeTransceiverProxy                        : ", eth.wormholeTransceiverProxy);
        console2.log("\n");

        console2.log("polygon.nttManagerProxy.getPeer().peerAddress       : ",  address(uint160(uint256(nttManagerPeer.peerAddress))));
        console2.log("eth.nttManagerProxy                                 : ", eth.nttManagerProxy);
        console2.log("\n");

        console2.log("polygon.nttManagerProxy.getPeer().tokenDecimals     : ",  nttManagerPeer.tokenDecimals);
        console2.log("eth.uni.decimals()                                  : ", uint8(18));
        console2.log("\n");

        console2.log("polygon.wormholeTransceiverProxy.owner()            : ",  WormholeTransceiver(polygon.wormholeTransceiverProxy).owner());
        console2.log("Constants.Polygon.UNISWAP_WORMHOLE_MESSAGE_RECEIVER : ", Constants.Polygon.UNISWAP_WORMHOLE_MESSAGE_RECEIVER);
        console2.log("\n");

        console2.log("polygon.nttManagerProxy.owner()                     : ",  NttManagerNoRateLimiting(polygon.nttManagerProxy).owner());
        console2.log("Constants.Polygon.UNISWAP_WORMHOLE_MESSAGE_RECEIVER : ", Constants.Polygon.UNISWAP_WORMHOLE_MESSAGE_RECEIVER);
        console2.log("\n");

        console2.log("polygon.nttManagerProxy.pauser()                    : ", NttManagerNoRateLimiting(polygon.nttManagerProxy).pauser());
        console2.log("address(0)                                          : ", address(0));
        console2.log("\n");

        // -----------------------------------------------------------------------------------------
        // Assertions
        //
        require(transceiverPeer == eth.wormholeTransceiverProxy);
        require(address(uint160(uint256(nttManagerPeer.peerAddress))) == eth.nttManagerProxy);
        require(nttManagerPeer.tokenDecimals == 18);
        require(WormholeTransceiver(polygon.wormholeTransceiverProxy).owner() == Constants.Polygon.UNISWAP_WORMHOLE_MESSAGE_RECEIVER);
        require(NttManagerNoRateLimiting(polygon.nttManagerProxy).owner() == Constants.Polygon.UNISWAP_WORMHOLE_MESSAGE_RECEIVER);
        require(NttManagerNoRateLimiting(polygon.nttManagerProxy).pauser() == address(0));

        vm.stopBroadcast();
    }

    /// @dev Loads deployments from most recent script run, writes them to the script's local
    ///      storage, then performs basic checks to reduce chance of bad configuration run.
    function loadDeployments() internal {
        // -----------------------------------------------------------------------------------------
        // Load Polygon addresses.
        //
        // Polygon Deployment Transaction Index Recap:
        //
        // | Index | Action                                                              |
        // | ----- | ------------------------------------------------------------------- |
        // | 00    | Deploy SyntheticNttUni.                                             |
        // | 01    | Deploy NttManager implementation.                                   |
        // | 02    | Deploy NttManager proxy.                                            |
        // | 03    | Initialize NttManager proxy.                                        |
        // | 04    | Deploy WormholeTransceiver implementation.                          |
        // | 05    | Deploy WormholeTransceiver proxy                                    |
        // | 06    | Initialize WormholeTransceiver proxy                                |
        // | 07    | Set NttManager proxy's transceiver to the WormholeTransceiver proxy |
        // | 08    | Set the threshold of transceiver attestation redundancy             |
        // | 09    | Set SyntheticNttUniNtt mint authority to NttManager proxy           |
        // | 10    | Transfer ownership of SyntheticNttUni to governance                 |
        //
        string memory polygonDeployJson = vm.readFile(POLYGON_DEPLOY_PATH);
        polygon = Deployment({
            uni: vm.parseJsonAddress(polygonDeployJson, ".transactions[0].contractAddress"),
            nttManagerImplementation: vm.parseJsonAddress(polygonDeployJson, ".transactions[1].contractAddress"),
            nttManagerProxy: vm.parseJsonAddress(polygonDeployJson, ".transactions[2].contractAddress"),
            wormholeTransceiverImplementation: vm.parseJsonAddress(polygonDeployJson, ".transactions[4].contractAddress"),
            wormholeTransceiverProxy: vm.parseJsonAddress(polygonDeployJson, ".transactions[5].contractAddress")
        });

        // -----------------------------------------------------------------------------------------
        // Load ETH addresses.
        //
        // ETH Deployment Transaction Index Recap:
        //
        // | Index | Action                                                              |
        // | ----- | ------------------------------------------------------------------- |
        // | 00    | Deploy NttManager implementation.                                   |
        // | 01    | Deploy NttManager proxy.                                            |
        // | 02    | Initialize NttManager proxy.                                        |
        // | 03    | Deploy WormholeTransceiver implementation.                          |
        // | 04    | Deploy WormholeTransceiver proxy                                    |
        // | 05    | Initialize WormholeTransceiver proxy                                |
        // | 06    | Set NttManager proxy's transceiver to the WormholeTransceiver proxy |
        // | 07    | Set the threshold of transceiver attestation redundancy             |
        //
        string memory ethDeployJson = vm.readFile(ETH_DEPLOY_PATH);
        eth = Deployment({
            uni: Constants.Ethereum.UNI,
            nttManagerImplementation: vm.parseJsonAddress(ethDeployJson, ".transactions[0].contractAddress"),
            nttManagerProxy: vm.parseJsonAddress(ethDeployJson, ".transactions[1].contractAddress"),
            wormholeTransceiverImplementation: vm.parseJsonAddress(ethDeployJson, ".transactions[3].contractAddress"),
            wormholeTransceiverProxy: vm.parseJsonAddress(ethDeployJson, ".transactions[4].contractAddress")
        });

        // -----------------------------------------------------------------------------------------
        // Run basic smoke checks on Polygon.
        //
        // Calls against Ethereum deployments are not possible, given this script targets Polygon.
        //

        // Check contracts have non-zero code length.
        //
        require(polygon.uni.code.length != 0, "SyntheticNttUni has no code.");
        require(polygon.nttManagerImplementation.code.length != 0, "NttManager implementation has no code.");
        require(polygon.nttManagerProxy.code.length != 0, "NttManager proxy has no code.");
        require(polygon.wormholeTransceiverImplementation.code.length != 0, "WormholeTransceiver implementation has no code.");
        require(polygon.wormholeTransceiverProxy.code.length != 0, "WormholeTransceiver proxy has no code.");

        // Check UNI metadata.
        //
        require(keccak256(bytes(SyntheticNttUni(polygon.uni).name())) == keccak256("Synthetic Ntt Uniswap"), "polygon.uni.name() mismatch");
        require(keccak256(bytes(SyntheticNttUni(polygon.uni).symbol())) == keccak256("NUNI"), "polygon.uni.symbol() mismatch");
        require(SyntheticNttUni(polygon.uni).decimals() == 18, "polygon.uni.decimals() mismatch");
        require(SyntheticNttUni(polygon.uni).ntt() == polygon.nttManagerProxy, "polygon.uni.ntt() mismatch");
        require(SyntheticNttUni(polygon.uni).owner() == Constants.Polygon.WORMHOLE_RECEIVER, "polygon.uni.owner() mismatch");

        // Check NttManager proxy.
        //
        NttManagerNoRateLimiting.TransceiverInfo[] memory transceiverInfos =
            NttManagerNoRateLimiting(polygon.nttManagerProxy).getTransceiverInfo();

        require(readImplementation(polygon.nttManagerProxy) == polygon.nttManagerImplementation, "polygon.nttManagerProxy.implementation() mismatch");
        require(NttManagerNoRateLimiting(polygon.nttManagerProxy).getMode() == uint8(IManagerBase.Mode.BURNING), "polygon.nttManagerProxy.mode() mismatch");
        require(NttManagerNoRateLimiting(polygon.nttManagerProxy).token() == polygon.uni, "polygon.nttManagerProxy.token() mismatch");
        require(NttManagerNoRateLimiting(polygon.nttManagerProxy).getThreshold() == 1, "polygon.nttManagerProxy.getThreshold() mismatch");
        require(transceiverInfos.length == 1, "nttManagerProxy.getTransceiverInfo().length mismatch");
        require(transceiverInfos[0].registered == true, "nttManagerProxy.getTransceiverInfo()[0].registered mismatch");
        require(transceiverInfos[0].enabled == true, "nttManagerProxy.getTransceiverInfo()[0].enabled mismatch");
        require(transceiverInfos[0].index == 0, "nttManagerProxy.getTransceiverInfo()[0].index mismatch");

        // Check WormholeTransceiver proxy.
        //
        require(readImplementation(polygon.wormholeTransceiverProxy) == polygon.wormholeTransceiverImplementation, "polygon.nttManagerProxy.implementation() mismatch");
        require(WormholeTransceiver(polygon.wormholeTransceiverProxy).nttManager() == polygon.nttManagerProxy, "wormholeTransceiverProxy.nttManager() mismatch");
        require(WormholeTransceiver(polygon.wormholeTransceiverProxy).nttManagerToken() == polygon.uni, "wormholeTransceiverProxy.nttManagerToken() mismatch");
        require(WormholeTransceiver(polygon.wormholeTransceiverProxy).consistencyLevel() == 202, "wormholeTransceiverProxy.consistencyLevel() mismatch");
        require(WormholeTransceiver(polygon.wormholeTransceiverProxy).customConsistencyLevel() == 0, "wormholeTransceiverProxy.customConsistencyLevel() mismatch");
        require(WormholeTransceiver(polygon.wormholeTransceiverProxy).additionalBlocks() == 0, "wormholeTransceiverProxy.additionalBlocks() mismatch");
        require(WormholeTransceiver(polygon.wormholeTransceiverProxy).customConsistencyLevelAddress() == address(0x00), "wormholeTransceiverProxy.customConsistencyLevelAddress() mismatch");
        require(address(WormholeTransceiver(polygon.wormholeTransceiverProxy).wormhole()) == Constants.Polygon.WORMHOLE, "wormholeTransceiverProxy.wormhole() mismatch");
    }

    function readImplementation(address proxy) internal view returns (address) {
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 value = vm.load(proxy, IMPLEMENTATION_SLOT);

        return address(uint160(uint256(value)));
    }
}
