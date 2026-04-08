// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import "../Constants.sol" as Constants;
import {IWormhole} from "../Interfaces.sol";

import {NttManagerNoRateLimiting, Mode} from "lib/native-token-transfers/evm/src/NttManager/NttManagerNoRateLimiting.sol";
import {WormholeTransceiver} from "lib/native-token-transfers/evm/src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// -------------------------------------------------------------------------------------------------
// NOTICE:
//
// This deployment script necessitates a balance of the native token (Ether's equivalent on BNB)
// both to pay for gas **and** to pay for a wormhole core message.
//
// Get the BNB RPC URL here: https://chainlist.org/chain/56
//
// Set the BNB RPC URL
//
// Query the message fee here:
//
// cast call 0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B "messageFee()(uint256)" --rpc-url https://bsc-rpc.publicnode.com
//
// Wormhole: https://bscscan.com/address/0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B
// Implementation: https://bscscan.com/address/0xc41172cc37e98bebd12abb39f9124a47e4d072ee
//
// ---
//
// PS: This appears to return `0` on BNB chain, so this may be unnecessry. It's unclear whether this
// is some kind of relayer fee or if it's some kind of protocol fee. Nonetheless, it's worth
// querying at deploy time to make sure there are no unexpected costs.
//
contract DeployWormholeInfraBNBChainScript is Script {
    address internal nttManagerProxy;
    address internal nttManagerImplementation;

    address internal wormholeTransceiverProxy;
    address internal wormholeTransceiverImplementation;

    function run() public {
        vm.startBroadcast();

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
                _token: Constants.BNB.UNI,
                _mode: Mode.BURNING,
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
        // This script also revokes authorization for upgrade to mitigate upgrade authority risk.
        //
        // - `implementation`: Implementation contract address.
        // - `data`: Optional call to make during deployment. We dont use this.
        //
        nttManagerProxy = address(new ERC1967Proxy({
            implementation: nttManagerImplementation,
            data: new bytes(0)
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
            data: new bytes(0)
        }));

        // -----------------------------------------------------------------------------------------
        // Query for Wormhole Message Fee.
        //
        uint256 messageFee = IWormhole(Constants.BNB.Wormhole).messageFee();

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
        // Set the transceiver to the WormholeTransceiver proxy on the NttManager proxy
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

        // TODO: transfer ownership of things to governance
        // TODO: check if configuration needs to run before ownership transfer to governance

        // -----------------------------------------------------------------------------------------
        // Logs
        //
        console2.log("-- DEPLOYMENTS --");
        console2.log("\n");
        console2.log("NttManager (ERC1967 Proxy):  ", nttManagerProxy);
        console2.log("NttManager (Implementation): ", nttManagerImplementation);
        console2.log("WormholeTransceiver (ERC1967Proxy): ", wormholeTransceiverProxy);
        console2.log("WormholeTransceiver (Implementation): ", wormholeTransceiverImplementation);
        console2.log("\n");
        console2.log("-- VISUALIZED ASSERTIONS --");
        console2.log("\n");
        console2.log("nttManagerProxy.implementation(), nttManagerImplementation:");
        console2.log("nttManagerProxy.implementation() -> ", NttManagerNoRateLimiting(nttManagerProxy).implementation());
        console2.log("nttManagerImplementation ---------> ", nttManagerImplementation);
        console2.log("\n");
        console2.log("wormholeTransceiverProxy.implementation() -> ", WormholeTransceiver(wormholeTransceiverProxy).implementation());
        console2.log("wormholeTransceiverImplementation ---------> ", wormholeTransceiverImplementation);
        console2.log("\n");
        console2.log("wormholeTransceiverProxy.implementation() -> ", WormholeTransceiver(wormholeTransceiverProxy).implementation());
        console2.log("wormholeTransceiverImplementation ---------> ", wormholeTransceiverImplementation);
        // TODO: finish this.

        // -----------------------------------------------------------------------------------------
        // Assertions
        //

        // TODO: assert what's above.

        vm.stopBroadcast();
    }
}
