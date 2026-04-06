// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

// interface ITokenReceiver {

// }

contract CrossChainReceiver {
    address public immutable TOKEN_BRIDGE;
    address public immutable WORMHOLE;

    constructor(
        address tokenBridge,
        address wormhole
    ) {
        TOKEN_BRIDGE = tokenBridge;
        WORMHOLE = wormhole;
    }

    function redeem(bytes memory encodedVm) external {
        bytes memory payload; // = tokenBridge.completeTransferWithPayload(encodedVm);

        // ...
    }
}
