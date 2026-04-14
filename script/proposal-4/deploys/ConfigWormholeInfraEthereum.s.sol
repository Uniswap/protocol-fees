// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import "../Constants.sol" as Constants;
import {IWormhole} from "../Interfaces.sol";

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
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

contract ConfigWormholeInfraEthereumScript is Script {
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
        uint256 messageFee = IWormhole(Constants.L1.WORMHOLE).messageFee();

        // -----------------------------------------------------------------------------------------
        // Transaction 00
        //
        // Set BNBChain WormholeTransceiver proxy as a peer on the BNBChain Chain Id.
        //
        // Parameters:
        //
        // - `peerChainId`: Wormhole-defined BNBChain Chain Id.
        // - `peerContract`: BNBChain WormholeTransceiver proxy.
        //
        WormholeTransceiver(eth.wormholeTransceiverProxy).setWormholePeer{value: messageFee}({
            peerChainId: Constants.Wormhole.BNB_CHAIN_ID,
            peerContract: bytes32(uint256(uint160(bnb.wormholeTransceiverProxy)))
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 01
        //
        // Sets the NttManager Proxy on BNBChain as a peer.
        //
        // Parameters:
        //
        // - `peerChainId`: Womrhole-defined BNBChain Chain Id.
        // - `peerContract: BNBChain NttManager proxy.
        // - `decimals`: SyntheticNttUni decimals on BNBChain.
        // - `inboundLimit`: Set to zero when rate limiter is disabled [1].
        //
        // Sources:
        //
        // [1] https://github.com/wormhole-foundation/native-token-transfers/blob/main/evm/README.md
        NttManagerNoRateLimiting(eth.nttManagerProxy).setPeer({
            peerChainId: Constants.Wormhole.BNB_CHAIN_ID,
            peerContract: bytes32(uint256(uint160(bnb.nttManagerProxy))),
            decimals: 18,
            inboundLimit: 0
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 02
        //
        // Transfer proxy ownership to Timelock.
        //
        // Parameters:
        //
        // - `newOwner`: Governance-owned Timelock.
        //
        NttManagerNoRateLimiting(eth.nttManagerProxy).transferOwnership({
            newOwner: Constants.L1.TIMELOCK
        });

        // Query Peer data for checks
        //
        address transceiverPeer = address(uint160(uint256(WormholeTransceiver(eth.wormholeTransceiverProxy).getWormholePeer(Constants.Wormhole.BNB_CHAIN_ID))));

        NttManagerNoRateLimiting.NttManagerPeer memory nttManagerPeer =
            NttManagerNoRateLimiting(eth.nttManagerProxy).getPeer(Constants.Wormhole.BNB_CHAIN_ID);

        // -----------------------------------------------------------------------------------------
        // Logs
        //
        console2.log("-- VISUALIZED ASSERTIONS -----------------------------");
        console2.log("\n");

        console2.log("eth.wormholeTransceiverProxy.getWormholePeer()    : ",  transceiverPeer);
        console2.log("bnb.wormholeTransceiverProxy                      : ", bnb.wormholeTransceiverProxy);
        console2.log("\n");

        console2.log("eth.nttManagerProxy.getPeer().peerAddress         : ",  address(uint160(uint256(nttManagerPeer.peerAddress))));
        console2.log("bnb.nttManagerProxy                               : ", bnb.nttManagerProxy);
        console2.log("\n");

        console2.log("eth.nttManagerProxy.getPeer().tokenDecimals       : ",  nttManagerPeer.tokenDecimals);
        console2.log("bnb.uni.decimals()                                : ", uint8(18));
        console2.log("\n");

        console2.log("eth.nttManagerProxy.owner()                       : ",  NttManagerNoRateLimiting(eth.nttManagerProxy).owner());
        console2.log("Constants.L1.TIMELOCK                             : ", Constants.L1.TIMELOCK);
        console2.log("\n");

        // -----------------------------------------------------------------------------------------
        // Assertions
        //
        require(transceiverPeer == bnb.wormholeTransceiverProxy);
        require(address(uint160(uint256(nttManagerPeer.peerAddress))) == bnb.nttManagerProxy);
        require(nttManagerPeer.tokenDecimals == 18);
        require(NttManagerNoRateLimiting(eth.nttManagerProxy).owner() == Constants.L1.TIMELOCK);

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
        // Run basic smoke checks on Ethereum.
        //
        // Calls against BNBChain deployments are not possible, given this script targets Ethereum.
        //

        // Check contracts have non-zero code length.
        //
        require(eth.uni.code.length != 0, "UNI has no code.");
        require(eth.nttManagerImplementation.code.length != 0, "NttManager implementation has no code.");
        require(eth.nttManagerProxy.code.length != 0, "NttManager proxy has no code.");
        require(eth.wormholeTransceiverImplementation.code.length != 0, "WormholeTransceiver implementation has no code.");
        require(eth.wormholeTransceiverProxy.code.length != 0, "WormholeTransceiver proxy has no code.");

        // Check UNI metadata.
        //
        require(keccak256(bytes(ERC20(eth.uni).name())) == keccak256("Uniswap"), "eth.uni.name() mismatch");
        require(keccak256(bytes(ERC20(eth.uni).symbol())) == keccak256("UNI"), "eth.uni.symbol() mismatch");
        require(SyntheticNttUni(eth.uni).decimals() == 18, "eth.uni.decimals() mismatch");
        require(SyntheticNttUni(eth.uni).ntt() == eth.nttManagerProxy, "eth.uni.ntt() mismatch");
        require(SyntheticNttUni(eth.uni).owner() == Constants.L1.WORMHOLE_RECEIVER, "eth.uni.owner() mismatch");

        // Check NttManager proxy.
        //
        NttManagerNoRateLimiting.TransceiverInfo[] memory transceiverInfos =
            NttManagerNoRateLimiting(eth.nttManagerProxy).getTransceiverInfo();

        require(readImplementation(eth.nttManagerProxy) == eth.nttManagerImplementation, "eth.nttManagerProxy.implementation() mismatch");
        require(NttManagerNoRateLimiting(eth.nttManagerProxy).getMode() == uint8(IManagerBase.Mode.BURNING), "eth.nttManagerProxy.mode() mismatch");
        require(NttManagerNoRateLimiting(eth.nttManagerProxy).token() == eth.uni, "eth.nttManagerProxy.token() mismatch");
        require(NttManagerNoRateLimiting(eth.nttManagerProxy).getThreshold() == 1, "eth.nttManagerProxy.getThreshold() mismatch");
        require(transceiverInfos.length == 1, "nttManagerProxy.getTransceiverInfo().length mismatch");
        require(transceiverInfos[0].registered == true, "nttManagerProxy.getTransceiverInfo()[0].registered mismatch");
        require(transceiverInfos[0].enabled == true, "nttManagerProxy.getTransceiverInfo()[0].enabled mismatch");
        require(transceiverInfos[0].index == 0, "nttManagerProxy.getTransceiverInfo()[0].index mismatch");

        // Check WormholeTransceiver proxy.
        //
        require(readImplementation(eth.wormholeTransceiverProxy) == eth.wormholeTransceiverImplementation, "eth.nttManagerProxy.implementation() mismatch");
        require(WormholeTransceiver(eth.wormholeTransceiverProxy).nttManager() == eth.nttManagerProxy, "wormholeTransceiverProxy.nttManager() mismatch");
        require(WormholeTransceiver(eth.wormholeTransceiverProxy).nttManagerToken() == eth.uni, "wormholeTransceiverProxy.nttManagerToken() mismatch");
        require(WormholeTransceiver(eth.wormholeTransceiverProxy).consistencyLevel() == 202, "wormholeTransceiverProxy.consistencyLevel() mismatch");
        require(WormholeTransceiver(eth.wormholeTransceiverProxy).customConsistencyLevel() == 0, "wormholeTransceiverProxy.customConsistencyLevel() mismatch");
        require(WormholeTransceiver(eth.wormholeTransceiverProxy).additionalBlocks() == 0, "wormholeTransceiverProxy.additionalBlocks() mismatch");
        require(WormholeTransceiver(eth.wormholeTransceiverProxy).customConsistencyLevelAddress() == address(0x00), "wormholeTransceiverProxy.customConsistencyLevelAddress() mismatch");
        require(address(WormholeTransceiver(eth.wormholeTransceiverProxy).wormhole()) == Constants.L1.WORMHOLE, "wormholeTransceiverProxy.wormhole() mismatch");
    }

    function readImplementation(address proxy) internal view returns (address) {
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 value = vm.load(proxy, IMPLEMENTATION_SLOT);

        return address(uint160(uint256(value)));
    }
}
