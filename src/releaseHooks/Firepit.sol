// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IReleaseHook} from "../interfaces/IReleaseHook.sol";
import {BURN_ADDRESS} from "../libraries/BurnAddress.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract Firepit is IReleaseHook {
    address public immutable RELEASER;

    constructor(address releaser) {
        RELEASER = releaser;
    }
    
    function afterRelease(address resource, uint256 threshold) external payable {
        require(msg.sender == RELEASER);

        ERC20(resource).transfer(BURN_ADDRESS, threshold);
    }
}
