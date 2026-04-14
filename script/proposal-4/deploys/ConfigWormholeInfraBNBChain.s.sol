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
// This configuration script MUST be run after both deployment scripts:
//
// 1. `script/proposal-4/deploys/DepoyWormholeInfraBNBChain.s.sol:DepoyWormholeInfraBNBChainScript`
// 2. `script/proposal-4/deploys/DeployWormholeInfraEthereum.s.sol:DeployWormholeInfraEthereumScript`
//
// The output of that run is written by Foundry into the following file path. If the latest is
// incorrect and we need to use it against another deployment, change this path:
string constant BNB_DEPLOY_PATH = "broadcast/DepoyWormholeInfraBNBChain.s.sol/56/run-latest.json";
string constant ETH_DEPLOY_PATH = "broadcast/DeployWormholeInfraEthereum.s.sol/1/run-latest.json";

/// @dev Deployment script outputs.
struct Deployment {
    // On BNB, this is SyntheticNttUni.
    // On ETH, this is the canonical UNI.
    address uni;
    address nttManagerImplementation;
    address nttManagerProxy;
    address wormholeTransceiverImplementation;
    address wormholeTransceiverProxy;
}

contract ConfigWormholeInfraBNBChainScript is Script {
    Deployment bnb;
    Deployment eth;

    function run() public {
        Constants.smokeCheck();

        // loads json files of BNB and ETH deployments and stores them locally in this script.
        loadDeployments();

        vm.startBroadcast();

        // -----------------------------------------------------------------------------------------
        // Query for Wormhole Message Fee.
        //
        uint256 messageFee = IWormhole(Constants.BNB.WORMHOLE).messageFee();

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
        WormholeTransceiver(bnb.wormholeTransceiverProxy).setWormholePeer{value: messageFee}({
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
        NttManagerNoRateLimiting(bnb.nttManagerProxy).setPeer({
            peerChainId: Constants.Wormhole.ETH_CHAIN_ID,
            peerContract: bytes32(uint256(uint160(eth.nttManagerProxy))),
            decimals: 18,
            inboundLimit: 0
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 02
        //
        // Transfer proxy ownership to UniswapWormholeMessageReceiver.
        //
        // Parameters:
        //
        // - `newOwner`: Governance-owned Timelock.
        //
        NttManagerNoRateLimiting(bnb.nttManagerProxy).transferOwnership({
            newOwner: Constants.L1.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
        });

        // Query Peer data for checks
        //
        address transceiverPeer = address(uint160(uint256(WormholeTransceiver(bnb.wormholeTransceiverProxy).getWormholePeer(Constants.Wormhole.ETH_CHAIN_ID))));

        NttManagerNoRateLimiting.NttManagerPeer memory nttManagerPeer =
            NttManagerNoRateLimiting(bnb.nttManagerProxy).getPeer(Constants.Wormhole.ETH_CHAIN_ID);

        // -----------------------------------------------------------------------------------------
        // Logs
        //
        console2.log("-- VISUALIZED ASSERTIONS -----------------------------");
        console2.log("\n");

        console2.log("bnb.wormholeTransceiverProxy.getWormholePeer()    : ",  transceiverPeer);
        console2.log("eth.wormholeTransceiverProxy                      : ", eth.wormholeTransceiverProxy);
        console2.log("\n");

        console2.log("bnb.nttManagerProxy.getPeer().peerAddress         : ",  address(uint160(uint256(nttManagerPeer.peerAddress))));
        console2.log("eth.nttManagerProxy                               : ", eth.nttManagerProxy);
        console2.log("\n");

        console2.log("bnb.nttManagerProxy.getPeer().tokenDecimals       : ",  nttManagerPeer.tokenDecimals);
        console2.log("eth.uni.decimals()                                : ", uint8(18));
        console2.log("\n");

        console2.log("bnb.nttManagerProxy.owner()                       : ",  NttManagerNoRateLimiting(bnb.nttManagerProxy).owner());
        console2.log("Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER   : ", Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER);
        console2.log("\n");

        // -----------------------------------------------------------------------------------------
        // Assertions
        //
        require(transceiverPeer == eth.wormholeTransceiverProxy);
        require(address(uint160(uint256(nttManagerPeer.peerAddress))) == eth.nttManagerProxy);
        require(nttManagerPeer.tokenDecimals == 18);
        require(NttManagerNoRateLimiting(bnb.nttManagerProxy).owner() == Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER);

        vm.stopBroadcast();
    }

    /// @dev Loads deployments from most recent script run, writes them to the script's local
    ///      storage, then performs basic checks to reduce chance of bad configuration run.
    function loadDeployments() internal {
        // -----------------------------------------------------------------------------------------
        // Load BNB addresses.
        //
        // BNB Deployment Transaction Index Recap:
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
        string memory bnbDeployJson = vm.readFile(BNB_DEPLOY_PATH);
        bnb = Deployment({
            uni: vm.parseJsonAddress(bnbDeployJson, ".transactions[0].contractAddress"),
            nttManagerImplementation: vm.parseJsonAddress(bnbDeployJson, ".transactions[1].contractAddress"),
            nttManagerProxy: vm.parseJsonAddress(bnbDeployJson, ".transactions[2].contractAddress"),
            wormholeTransceiverImplementation: vm.parseJsonAddress(bnbDeployJson, ".transactions[4].contractAddress"),
            wormholeTransceiverProxy: vm.parseJsonAddress(bnbDeployJson, ".transactions[5].contractAddress")
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
            uni: Constants.L1.UNI,
            nttManagerImplementation: vm.parseJsonAddress(ethDeployJson, ".transactions[0].contractAddress"),
            nttManagerProxy: vm.parseJsonAddress(ethDeployJson, ".transactions[1].contractAddress"),
            wormholeTransceiverImplementation: vm.parseJsonAddress(ethDeployJson, ".transactions[3].contractAddress"),
            wormholeTransceiverProxy: vm.parseJsonAddress(ethDeployJson, ".transactions[4].contractAddress")
        });

        // -----------------------------------------------------------------------------------------
        // Run basic smoke checks on BNBChain.
        //
        // Calls against Ethereum deployments are not possible, given this script targets BNBChain.
        //

        // Check contracts have non-zero code length.
        //
        require(bnb.uni.code.length != 0, "SyntheticNttUni has no code.");
        require(bnb.nttManagerImplementation.code.length != 0, "NttManager implementation has no code.");
        require(bnb.nttManagerProxy.code.length != 0, "NttManager proxy has no code.");
        require(bnb.wormholeTransceiverImplementation.code.length != 0, "WormholeTransceiver implementation has no code.");
        require(bnb.wormholeTransceiverProxy.code.length != 0, "WormholeTransceiver proxy has no code.");

        // Check UNI metadata.
        //
        require(keccak256(bytes(SyntheticNttUni(bnb.uni).name())) == keccak256("Synthetic Ntt Uniswap"), "bnb.uni.name() mismatch");
        require(keccak256(bytes(SyntheticNttUni(bnb.uni).symbol())) == keccak256("NUNI"), "bnb.uni.symbol() mismatch");
        require(SyntheticNttUni(bnb.uni).decimals() == 18, "bnb.uni.decimals() mismatch");
        require(SyntheticNttUni(bnb.uni).ntt() == bnb.nttManagerProxy, "bnb.uni.ntt() mismatch");
        require(SyntheticNttUni(bnb.uni).owner() == Constants.BNB.WORMHOLE_RECEIVER, "bnb.uni.owner() mismatch");

        // Check NttManager proxy.
        //
        NttManagerNoRateLimiting.TransceiverInfo[] memory transceiverInfos =
            NttManagerNoRateLimiting(bnb.nttManagerProxy).getTransceiverInfo();

        require(readImplementation(bnb.nttManagerProxy) == bnb.nttManagerImplementation, "bnb.nttManagerProxy.implementation() mismatch");
        require(NttManagerNoRateLimiting(bnb.nttManagerProxy).getMode() == uint8(IManagerBase.Mode.BURNING), "bnb.nttManagerProxy.mode() mismatch");
        require(NttManagerNoRateLimiting(bnb.nttManagerProxy).token() == bnb.uni, "bnb.nttManagerProxy.token() mismatch");
        require(NttManagerNoRateLimiting(bnb.nttManagerProxy).getThreshold() == 1, "bnb.nttManagerProxy.getThreshold() mismatch");
        require(transceiverInfos.length == 1, "nttManagerProxy.getTransceiverInfo().length mismatch");
        require(transceiverInfos[0].registered == true, "nttManagerProxy.getTransceiverInfo()[0].registered mismatch");
        require(transceiverInfos[0].enabled == true, "nttManagerProxy.getTransceiverInfo()[0].enabled mismatch");
        require(transceiverInfos[0].index == 0, "nttManagerProxy.getTransceiverInfo()[0].index mismatch");

        // Check WormholeTransceiver proxy.
        //
        require(readImplementation(bnb.wormholeTransceiverProxy) == bnb.wormholeTransceiverImplementation, "bnb.nttManagerProxy.implementation() mismatch");
        require(WormholeTransceiver(bnb.wormholeTransceiverProxy).nttManager() == bnb.nttManagerProxy, "wormholeTransceiverProxy.nttManager() mismatch");
        require(WormholeTransceiver(bnb.wormholeTransceiverProxy).nttManagerToken() == bnb.uni, "wormholeTransceiverProxy.nttManagerToken() mismatch");
        require(WormholeTransceiver(bnb.wormholeTransceiverProxy).consistencyLevel() == 202, "wormholeTransceiverProxy.consistencyLevel() mismatch");
        require(WormholeTransceiver(bnb.wormholeTransceiverProxy).customConsistencyLevel() == 0, "wormholeTransceiverProxy.customConsistencyLevel() mismatch");
        require(WormholeTransceiver(bnb.wormholeTransceiverProxy).additionalBlocks() == 0, "wormholeTransceiverProxy.additionalBlocks() mismatch");
        require(WormholeTransceiver(bnb.wormholeTransceiverProxy).customConsistencyLevelAddress() == address(0x00), "wormholeTransceiverProxy.customConsistencyLevelAddress() mismatch");
        require(address(WormholeTransceiver(bnb.wormholeTransceiverProxy).wormhole()) == Constants.BNB.WORMHOLE, "wormholeTransceiverProxy.wormhole() mismatch");
    }

    function readImplementation(address proxy) internal view returns (address) {
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 value = vm.load(proxy, IMPLEMENTATION_SLOT);

        return address(uint160(uint256(value)));
    }
}
