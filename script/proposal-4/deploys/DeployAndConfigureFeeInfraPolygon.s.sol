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
// The output of those runs are written by Foundry into the following file paths. If the latest is
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

contract DeployAndConfigureFeeInfraPolygonScript is Script {
    Deployment internal polygon;

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
        // - `_nttManager`: Polygon NttManager proxy.
        // - `_resource`: Polygon SyntheticNttUni.
        // - `_threshold`: Minimum amount of `SyntheticNttUni` required to release.
        // - `_tokenJar`: `TokenJar`.
        //
        releaser = new WormholeReleaser{salt: RELEASER_SALT}({
            _nttManager: polygon.nttManagerProxy,
            _resource: polygon.uni,
            _threshold: Constants.Polygon.RELEASER_THRESHOLD,
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
            newOwner: Constants.Polygon.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
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
            _thresholdSetter: Constants.Polygon.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
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
            newOwner: Constants.Polygon.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 06
        //
        // Deploy `V3OpenFeeAdapter`.
        //
        // Parameters:
        //
        // - `_factory`: Polygon Uniswap V3 Factory.
        // - `_tokenJar: `TokenJar`.
        //
        v3OpenFeeAdapter = new V3OpenFeeAdapter{salt: FEE_ADAPTER_SALT}({
            _factory: Constants.Polygon.V3_FACTORY,
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
            newFeeSetter: Constants.Polygon.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
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
            newOwner: Constants.Polygon.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
        });

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
