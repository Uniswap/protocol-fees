// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IReleaseHook} from "../interfaces/IReleaseHook.sol";
import {IL2StandardBridge} from "../interfaces/external/IL2StandardBridge.sol";
import {BURN_ADDRESS} from "../libraries/BurnAddress.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract OpStackHook is IReleaseHook {
    address public immutable RELEASER;
    address public immutable L2_STANDARD_BRIDGE;
    uint32 public immutable WITHDRAWAL_MIN_GAS;

    constructor(address releaser, address l2StandardBridge, uint32 withdrawalMinGas) {
        RELEASER = releaser;
        L2_STANDARD_BRIDGE = l2StandardBridge;
        WITHDRAWAL_MIN_GAS = withdrawalMinGas;
    }

    function afterRelease(address resource, uint256 threshold) external payable {
        require(msg.sender == RELEASER);

        IL2StandardBridge(L2_STANDARD_BRIDGE).withdrawTo({
            _l2Token: resource,
            _to: BURN_ADDRESS,
            _amount: threshold,
            _minGasLimit: WITHDRAWAL_MIN_GAS,
            _extraData: new bytes(0)
        });
    }
}
