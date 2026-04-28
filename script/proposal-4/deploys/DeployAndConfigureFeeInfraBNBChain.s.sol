// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import {NttManagerNoRateLimiting} from "lib/native-token-transfers/evm/src/NttManager/NttManagerNoRateLimiting.sol";
import {WormholeTransceiver} from "lib/native-token-transfers/evm/src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";
import {IManagerBase} from "lib/native-token-transfers/evm/src/interfaces/IManagerBase.sol";

import {SyntheticNttUni} from "../../../src/wormhole/SyntheticNttUni.sol";
import {TokenJar} from "../../../src/TokenJar.sol";
import {WormholeReleaser} from "../../../src/releasers/WormholeReleaser.sol";
import {V3OpenFeeAdapter} from "../../../src/feeAdapters/V3OpenFeeAdapter.sol";
import "../Constants.sol" as Constants;

bytes32 constant TOKEN_JAR_SALT = bytes32(uint256(67));
bytes32 constant RELEASER_SALT = bytes32(uint256(67));
bytes32 constant FEE_ADAPTER_SALT = bytes32(uint256(67));

// Protocol fee defaults — same as mainnet
uint8 constant DEFAULT_FEE_100 = (4 << 4) | 4; // 1/4 for 0.01% tier
uint8 constant DEFAULT_FEE_500 = (4 << 4) | 4; // 1/4 for 0.05% tier
uint8 constant DEFAULT_FEE_3000 = (6 << 4) | 6; // 1/6 for 0.30% tier
uint8 constant DEFAULT_FEE_10000 = (6 << 4) | 6; // 1/6 for 1.00% tier

// -------------------------------------------------------------------------------------------------
// NOTICE:
//
// This script depends on the following scripts to have been run:
//
// 1. `script/proposal-4/deploys/DepoyWormholeInfraBNBChain.s.sol:DepoyWormholeInfraBNBChainScript`
// 2. `script/proposal-4/deploys/DeployWormholeInfraEthereum.s.sol:DeployWormholeInfraEthereumScript`
// 3. `script/proposal-4/deploys/ConfigWormholeInfraBNBChain.s.sol:ConfigWormholeInfraBNBChainScript`
// 4. `script/proposal-4/deploys/ConfigWormholeInfraEthereum.s.sol:ConfigWormholeInfraEthereumScript`
//
// The output of the BNB Chain deployment run is written by Foundry into the following file path. If
// the latest is incorrect and we need to use it against another deployment, change this path:
string constant BNB_DEPLOY_PATH = "broadcast/DepoyWormholeInfraBNBChain.s.sol/56/run-latest.json";

struct Deployment {
    // This is SyntheticNttUni.
    address uni;
    address nttManagerImplementation;
    address nttManagerProxy;
    address wormholeTransceiverImplementation;
    address wormholeTransceiverProxy;
}

contract DeployAndConfigureFeeInfraBNBChainScript is Script {
    Deployment internal bnb;

    TokenJar internal tokenJar;
    V3OpenFeeAdapter internal v3OpenFeeAdapter;
    WormholeReleaser internal releaser;

    function run() public {
        Constants.smokeCheck();

        loadDeployments();

        vm.startBroadcast();

        // -----------------------------------------------------------------------------------------
        // Transaction 00
        //
        // Deploy `TokenJar`.
        //
        tokenJar = new TokenJar{salt: TOKEN_JAR_SALT}();

        // -----------------------------------------------------------------------------------------
        // Transaction 01
        //
        // Deploy `WormholeReleaser`.
        //
        // Parameters:
        //
        // - `_nttManager`: BNBChain NttManager proxy.
        // - `_resource`: BNBChain SyntheticNttUni.
        // - `_threshold`: Minimum amount of `SyntheticNttUni` required to release.
        // - `_tokenJar`: `TokenJar`.
        //
        releaser = new WormholeReleaser{salt: RELEASER_SALT}({
            _nttManager: bnb.nttManagerProxy,
            _resource: bnb.uni,
            _threshold: Constants.BNB.RELEASER_THRESHOLD,
            _tokenJar: address(tokenJar)
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 02
        //
        // Set `WormholeReleaser` as the releaser on `TokenJar`.
        //
        // Parameters:
        //
        // - `_releaser`: `WormholeReleaser`.
        //
        tokenJar.setReleaser({
            _releaser: address(releaser)
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 03
        //
        // Transfer `TokenJar` ownership to `UniswapWormholeMessageReceiver`.
        //
        // Parameters:
        //
        // - `newOwner`: Governance-owned Wormhole message receiver.
        //
        tokenJar.transferOwnership({
            newOwner: Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 04
        //
        // Set `WormholeReleaser` threshold-setter to `UniswapWormholeMessageReceiver`.
        //
        // Parameters:
        //
        // - `_thresholdSetter`: Governance-owned Wormhole message receiver.
        //
        releaser.setThresholdSetter({
            _thresholdSetter: Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 05
        //
        // Transfer ownership of `WormholeReleaser` to `UniswapWormholeMessageReceiver`.
        //
        // Parameters:
        //
        // - `newOwner`: Governance-owned Wormhole message receiver.
        //
        releaser.transferOwnership({
            newOwner: Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 06
        //
        // Deploy `V3OpenFeeAdapter`.
        //
        // Parameters:
        //
        // - `_factory`: BNB Chain Uniswap V3 Factory.
        // - `_tokenJar: `TokenJar`.
        //
        v3OpenFeeAdapter = new V3OpenFeeAdapter{salt: FEE_ADAPTER_SALT}({
            _factory: Constants.BNB.V3_FACTORY,
            _tokenJar: address(tokenJar)
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 07
        //
        // Set `V3OpenFeeAdapter` fee-setter to the deployer for configuration.
        //
        // Paramters:
        //
        // - `newFeeSetter`: Deployer of the contract (owner).
        //
        // > Note: Foundry is not particularly clear about how to access the address of the EOA
        // > executing this script, but the `v3OpenFeeAdapter` assigns the `owner` to be the EOA
        // > which deployed it, so we query the fee adapter's owner to sidestep the issue.
        //
        v3OpenFeeAdapter.setFeeSetter({
            newFeeSetter: v3OpenFeeAdapter.owner()
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 08
        //
        // Set `V3OpenFeeAdapter` default fee.
        //
        // Parameters:
        //
        // - `feeValue`: Default fee value.
        //
        v3OpenFeeAdapter.setDefaultFee({
            feeValue: DEFAULT_FEE_100
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 09, 10, 11, 12
        //
        // Set `V3OpenFeeAdapter` fee tier defaults.
        //
        // Parameters:
        //
        // - `feeTier`: Fee tier to set.
        // - `feeValue`: Default fee value for the tier.
        //
        v3OpenFeeAdapter.setFeeTierDefault({
            feeTier: 100,
            feeValue: DEFAULT_FEE_100
        });

        v3OpenFeeAdapter.setFeeTierDefault({
            feeTier: 500,
            feeValue: DEFAULT_FEE_500
        });

        v3OpenFeeAdapter.setFeeTierDefault({
            feeTier: 3000,
            feeValue: DEFAULT_FEE_3000
        });

        v3OpenFeeAdapter.setFeeTierDefault({
            feeTier: 10_000,
            feeValue: DEFAULT_FEE_10000
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 13, 14, 15, 16
        //
        // Store `V3OpenFeeAdapter` fee tiers.
        //
        // - `feeTier`: Fee tiers which can be triggered for update.
        //
        v3OpenFeeAdapter.storeFeeTier({
            feeTier: 100
        });

        v3OpenFeeAdapter.storeFeeTier({
            feeTier: 500
        });

        v3OpenFeeAdapter.storeFeeTier({
            feeTier: 3000
        });

        v3OpenFeeAdapter.storeFeeTier({
            feeTier: 10_000
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 17
        //
        // Transfer `V3OpenFeeAdapter` fee setter permission to `UniswapWormholeMessageReceiver`.
        //
        // Parameters:
        //
        // - `newFeeSetter`: Governance-owned Wormhole message receiver.
        //
        v3OpenFeeAdapter.setFeeSetter({
            newFeeSetter: Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 18
        //
        // Transfer `V3OpenFeeAdapter` ownership to `UniswapWormholeMessageReceiver`.
        //
        // Parameters:
        //
        // - `newOwner`: Governance-owned Wormhole message receiver.
        //
        v3OpenFeeAdapter.transferOwnership({
            newOwner: Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
        });

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
