// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IReleaseHook} from "../interfaces/IReleaseHook.sol";
import {IL2GatewayRouter} from "../interfaces/external/IL2GatewayRouter.sol";
import {BURN_ADDRESS} from "../libraries/BurnAddress.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract ArbitrumOrbitHook is IReleaseHook {
    address public immutable RELEASER;
    address public immutable L2_GATEWAY_ROUTER;
    address public immutable L1_RESOURCE;

    constructor(address releaser, address l2GatewayRouter, address l1Resource) {
        RELEASER = releaser;
        L2_GATEWAY_ROUTER = l2GatewayRouter;
        L1_RESOURCE = l1Resource;
    }

    function afterRelease(address, uint256 threshold) external payable {
        require(msg.sender == RELEASER);

        IL2GatewayRouter(L2_GATEWAY_ROUTER).outboundTransfer({
            _l1Token: L1_RESOURCE,
            _to: BURN_ADDRESS,
            _amount: threshold,
            _data: new bytes(0)
        });
    }
}
