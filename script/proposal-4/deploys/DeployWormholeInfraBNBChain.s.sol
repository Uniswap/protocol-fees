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
// This deployment script necessitates a balance of the native token (Ether's equivalent on BNB)
// both to pay for gas **and** to pay for a wormhole core message.
//
// cast call 0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B "messageFee()(uint256)" --rpc-url https://bsc-rpc.publicnode.com
//
// Wormhole: https://bscscan.com/address/0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B
// Implementation: https://bscscan.com/address/0xc41172cc37e98bebd12abb39f9124a47e4d072ee
//
// ---
//
// UPDATE: This appears to return `0` on BNB chain, so this may be unnecessry. It's unclear whether
// this is some kind of relayer fee or if it's some kind of protocol fee. Nonetheless, it's worth
// querying at deploy time to make sure there are no unexpected costs.
//
contract DeployWormholeInfraBNBChainScript is Script {
    address internal nttManagerProxy;
    address internal nttManagerImplementation;

    address internal wormholeTransceiverProxy;
    address internal wormholeTransceiverImplementation;

    address internal syntheticNttUni;

    function run() public {
        Constants.smokeCheck();

        vm.startBroadcast();

        // -----------------------------------------------------------------------------------------
        // Transaction 00
        //
        // Deploy the SyntheticNttUni token.
        //
        syntheticNttUni = address(new SyntheticNttUni());

        // -----------------------------------------------------------------------------------------
        // Transaction 01
        //
        // Deploy NttManager implementation with no rate limiting.
        //
        // - `_token`: BNB deployment of UNI.
        // - `_mode`: `BURNING` for all foreign chains.
        // - `_chainId`: Wormhole-defined chain ID, not EIP155-defined.
        //
        nttManagerImplementation = address(
            new NttManagerNoRateLimiting({
                _token: syntheticNttUni,
                _mode: IManagerBase.Mode.BURNING,
                _chainId: Constants.Wormhole.BNB_CHAIN_ID
            })
        );

        // -----------------------------------------------------------------------------------------
        // Transaction 02
        //
        // Deploy NttManager proxy and set its implementation.
        //
        // We generally avoid using proxy-implementation pairs. Since Wormhole has only defined a
        // collection of NttManager systems as proxy implementations, though, it will be best to use
        // their code and simply avoid any potential mishaps on our end.
        //
        // There is a followup script which configures the NTT system that necessitates the full
        // authority, though that followup script transfer upgrade authority to the governance
        // receiver contract to mitigate upgrade authority risk.
        //
        // - `implementation`: Implementation contract address.
        // - `data`: Optional call to make during deployment. We dont use this.
        //
        nttManagerProxy = address(new ERC1967Proxy({
            implementation: nttManagerImplementation,
            _data: new bytes(0)
        }));

        // -----------------------------------------------------------------------------------------
        // Transaction 03
        //
        // Initialize NttManager proxy.
        //
        NttManagerNoRateLimiting(nttManagerProxy).initialize();

        // -----------------------------------------------------------------------------------------
        // Transaction 04
        //
        // Deploy WormholeTransceiver implementation.
        //
        // Parameters:
        //
        // - `nttManager`: NttManager proxy address.
        // - `wormholeCoreBridge`: Wormhole address.
        // - `_consistencyLevel`: Hardcoded to 202 in Wormhole documentation [1].
        // - `_customConsistencyLevel`: Unused when `_consistencyLevel != 203` [2].
        // - `_additionalBlocks`: Unused when `_consistencyLevel != 203` [2].
        // - `_customConsistencyLevelAddress`: Unused when `_consistencyLevel != 203` [2].
        //
        // Sources:
        //
        // [1] https://wormhole.com/docs/products/token-transfers/native-token-transfers/guides/deploy-to-evm/#ntt-manager-deployment-parameters
        // [2] https://github.com/wormhole-foundation/wormhole/blob/main/whitepapers/0001_generic_message_passing.md#custom-handling
        //
        wormholeTransceiverImplementation = address(
            new WormholeTransceiver({
                nttManager: nttManagerProxy,
                wormholeCoreBridge: Constants.BNB.WORMHOLE,
                _consistencyLevel: 202,
                _customConsistencyLevel: 0,
                _additionalBlocks: 0,
                _customConsistencyLevelAddress: address(0x00)
            })
        );

        // -----------------------------------------------------------------------------------------
        // Transaction 05
        //
        // Deploy WormholeTransceiver proxy.
        //
        wormholeTransceiverProxy = address(new ERC1967Proxy({
            implementation: wormholeTransceiverImplementation,
            _data: new bytes(0)
        }));

        // -----------------------------------------------------------------------------------------
        // Query for Wormhole Message Fee.
        //
        uint256 messageFee = IWormhole(Constants.BNB.WORMHOLE).messageFee();

        // -----------------------------------------------------------------------------------------
        // Transaction 06
        //
        // Initialize WormholeTransceiver proxy with a recently queried `messageFee`.
        //
        // Parameters:
        //
        // - `value`: Call value for a call to `wormhole.publishMessage` in the initializer.
        //
        WormholeTransceiver(wormholeTransceiverProxy).initialize{value: messageFee}();

        // -----------------------------------------------------------------------------------------
        // Transaction 07
        //
        // Set NttManager proxy's transceiver to the WormholeTransceiver proxy.
        //
        // Parameters:
        //
        // - `transceiver`: WormholeTransceiver proxy.
        //
        NttManagerNoRateLimiting(nttManagerProxy).setTransceiver({
            transceiver: wormholeTransceiverProxy
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 08
        //
        // Set the threshold of transceiver attestation redundancy. This gets set to `1` since it's
        // set to this in the wormhole team's deployment script. The wormhole team mentions this is
        // set to `1` because it handles "wormhole-only" deployments [1]. Unsure what this implies
        // about thresholds greater than one, but we'll leave it as-is for now.
        //
        // Parameters:
        //
        // - `threshold`: Threshold.
        //
        // Sources:
        //
        // [1] https://github.com/wormhole-foundation/native-token-transfers/blob/25a5c3f89446be499a89d1c453db996f29de9290/evm/script/helpers/DeployWormholeNttBase.sol#L133
        //
        NttManagerNoRateLimiting(nttManagerProxy).setThreshold({
            threshold: 1
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 09
        //
        // Set SyntheticNttUni mint authority to NttManager proxy.
        //
        // Paramters:
        //
        // - `newNtt`: NttManager proxy
        //
        SyntheticNttUni(syntheticNttUni).setNtt({
            newNtt: nttManagerProxy
        });

        // -----------------------------------------------------------------------------------------
        // Transaction 10
        //
        // Transfer ownership of SyntheticNttUni to governance.
        //
        // Paramters:
        //
        // - `newOwner`: Uniswap Wormhole Governance Receiver
        //
        SyntheticNttUni(syntheticNttUni).transferOwnership({
            newOwner: Constants.BNB.WORMHOLE_RECEIVER
        });

        // -----------------------------------------------------------------------------------------
        // Logs
        //
        NttManagerNoRateLimiting.TransceiverInfo[] memory transceiverInfos =
            NttManagerNoRateLimiting(nttManagerProxy).getTransceiverInfo();

        console2.log("-- DEPLOYMENTS --------------------------------------------");
        console2.log("\n");

        console2.log("SyntheticNttUni                                           : ", syntheticNttUni);
        console2.log("NttManager (ERC1967 Proxy)                                : ", nttManagerProxy);
        console2.log("NttManager (Implementation)                               : ", nttManagerImplementation);
        console2.log("WormholeTransceiver (ERC1967Proxy)                        : ", wormholeTransceiverProxy);
        console2.log("WormholeTransceiver (Implementation)                      : ", wormholeTransceiverImplementation);
        console2.log("\n");

        console2.log("-- VISUALIZED ASSERTIONS ----------------------------------");
        console2.log("\n");

        console2.log("syntheticNttUni.ntt()                                     : ", SyntheticNttUni(syntheticNttUni).ntt());
        console2.log("nttManagerProxy                                           : ", nttManagerProxy);
        console2.log("\n");

        console2.log("syntheticNttUni.owner()                                   : ", SyntheticNttUni(syntheticNttUni).owner());
        console2.log("BNB Wormhole Receiver                                     : ", Constants.BNB.WORMHOLE_RECEIVER);
        console2.log("\n");

        console2.log("nttManagerProxy ERC1967 Implementation                    : ", readImplementation(nttManagerProxy));
        console2.log("nttManagerImplementation                                  : ", nttManagerImplementation);
        console2.log("\n");

        console2.log("nttManagerProxy.getMode()                                 : ", NttManagerNoRateLimiting(nttManagerProxy).getMode());
        console2.log("IManagerBase.MODE.BURNING                                 : ", uint8(IManagerBase.Mode.BURNING));
        console2.log("\n");

        console2.log("nttManagerProxy.token()                                   : ", NttManagerNoRateLimiting(nttManagerProxy).token());
        console2.log("SyntheticNttUni                                           : ", syntheticNttUni);
        console2.log("\n");

        console2.log("nttManagerProxy.getThreshold()                            : ", NttManagerNoRateLimiting(nttManagerProxy).getThreshold());
        console2.log("NttManager Threshold                                      : ", uint8(1));
        console2.log("\n");

        console2.log("nttManagerProxy.getTransceiverInfo().length               : ", transceiverInfos.length);
        console2.log("NttManager Transceiver Count                              : ", uint256(1));
        console2.log("\n");

        console2.log("nttManagerProxy.getTransceiverInfo()[0].registered        : ", transceiverInfos[0].registered);
        console2.log("NttManager Transceiver 0 Registered                       : ", true);
        console2.log("\n");

        console2.log("nttManagerProxy.getTransceiverInfo()[0].enabled           : ", transceiverInfos[0].enabled);
        console2.log("NttManager Transceiver 0 Enabled                          : ", true);
        console2.log("\n");

        console2.log("nttManagerProxy.getTransceiverInfo()[0].index             : ", transceiverInfos[0].index);
        console2.log("NttManager Transceiver 0 Index                            : ", uint8(0));
        console2.log("\n");

        console2.log("wormholeTransceiverProxy ERC1967 Implementation           : ", readImplementation(wormholeTransceiverProxy));
        console2.log("wormholeTransceiverImplementation                         : ", wormholeTransceiverImplementation);
        console2.log("\n");

        console2.log("wormholeTransceiverProxy.nttManager()                     : ", WormholeTransceiver(wormholeTransceiverProxy).nttManager());
        console2.log("NttManager Proxy                                          : ", nttManagerProxy);
        console2.log("\n");
    
        console2.log("wormholeTransceiverProxy.nttManagerToken()                : ", WormholeTransceiver(wormholeTransceiverProxy).nttManagerToken());
        console2.log("SyntheticNttUni                                           : ", syntheticNttUni);
        console2.log("\n");
    
        console2.log("wormholeTransceiverProxy.consistencyLevel()               : ", WormholeTransceiver(wormholeTransceiverProxy).consistencyLevel());
        console2.log("Consistency Level (Hard coded)                            : ", uint8(202));
        console2.log("\n");
    
        console2.log("wormholeTransceiverProxy.customConsistencyLevel()         : ", WormholeTransceiver(wormholeTransceiverProxy).customConsistencyLevel());
        console2.log("Custom consistency Level (Hard coded)                     : ", uint8(0));
        console2.log("\n");
    
        console2.log("wormholeTransceiverProxy.additionalBlocks()               : ", WormholeTransceiver(wormholeTransceiverProxy).additionalBlocks());
        console2.log("Additional blocks (Hard coded)                            : ", uint16(0));
        console2.log("\n");
    
        console2.log("wormholeTransceiverProxy.customConsistencyLevelAddress()  : ", WormholeTransceiver(wormholeTransceiverProxy).customConsistencyLevelAddress());
        console2.log("Custom consistency level address                          : ", address(0x00));
        console2.log("\n");
    
        console2.log("wormholeTransceiverProxy.wormhole()                       : ", address(WormholeTransceiver(wormholeTransceiverProxy).wormhole()));
        console2.log("Wormhole                                                  : ", Constants.BNB.WORMHOLE);
        console2.log("\n");

        // -----------------------------------------------------------------------------------------
        // Assertions
        //
        require(SyntheticNttUni(syntheticNttUni).ntt() == nttManagerProxy);
        require(SyntheticNttUni(syntheticNttUni).owner() == Constants.BNB.WORMHOLE_RECEIVER);

        require(readImplementation(nttManagerProxy) == nttManagerImplementation);
        require(NttManagerNoRateLimiting(nttManagerProxy).getMode() == uint8(IManagerBase.Mode.BURNING));
        require(NttManagerNoRateLimiting(nttManagerProxy).token() == syntheticNttUni);
        require(NttManagerNoRateLimiting(nttManagerProxy).getThreshold() == 1);

        require(transceiverInfos.length == 1);
        require(transceiverInfos[0].registered == true);
        require(transceiverInfos[0].enabled == true);
        require(transceiverInfos[0].index == 0);

        require(readImplementation(wormholeTransceiverProxy) == wormholeTransceiverImplementation);
        require(WormholeTransceiver(wormholeTransceiverProxy).nttManager() == nttManagerProxy);
        require(WormholeTransceiver(wormholeTransceiverProxy).nttManagerToken() == syntheticNttUni);
        require(WormholeTransceiver(wormholeTransceiverProxy).consistencyLevel() == 202);
        require(WormholeTransceiver(wormholeTransceiverProxy).customConsistencyLevel() == 0);
        require(WormholeTransceiver(wormholeTransceiverProxy).additionalBlocks() == 0);
        require(WormholeTransceiver(wormholeTransceiverProxy).customConsistencyLevelAddress() == address(0x00));
        require(address(WormholeTransceiver(wormholeTransceiverProxy).wormhole()) == Constants.BNB.WORMHOLE);

        vm.stopBroadcast();
    }

    function readImplementation(address proxy) internal view returns (address) {
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 value = vm.load(proxy, IMPLEMENTATION_SLOT);

        return address(uint160(uint256(value)));
    }
}
