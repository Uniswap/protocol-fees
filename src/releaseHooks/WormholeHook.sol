// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {INttManager} from "../interfaces/wormhole/INttManager.sol";
import {IReleaseHook} from "../interfaces/IReleaseHook.sol";
import {BURN_ADDRESS} from "../libraries/BurnAddress.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract WormholeHook is IReleaseHook {
    address public immutable RELEASER;

    uint16 public constant ETH_WORMHOLE_CHAIN_ID = 2;

    address public immutable NTT_MANAGER;

    constructor(address releaser, address nttManager) {
        RELEASER = releaser;
        NTT_MANAGER = nttManager;
    }

    function afterRelease(address resource, uint256 threshold) external payable {
        require(msg.sender == RELEASER);

        (, uint256 totalQuote) = INttManager(NTT_MANAGER).quoteDeliveryPrice({
        recipientChain: ETH_WORMHOLE_CHAIN_ID, transceiverInstructions: new bytes(1)
        });

        require(msg.value == totalQuote);

        uint256 amount = wormholeTrim(threshold);

        ERC20(resource).approve(NTT_MANAGER, amount);

        INttManager(NTT_MANAGER).transfer{value: totalQuote}({
            amount: amount,
            recipientChain: ETH_WORMHOLE_CHAIN_ID,
            recipient: bytes32(uint256(uint160(BURN_ADDRESS)))
        });
    }

    function wormholeTrim(uint256 amount) public pure returns (uint256) {
        return amount / 1e10 * 1e10;
    }
}
