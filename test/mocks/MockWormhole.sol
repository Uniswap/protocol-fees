// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IWormhole} from "../../src/interfaces/wormhole/IWormhole.sol";

contract MockWormhole is IWormhole {
    uint256 public messageFee;

    function mockSetMessageFee(uint256 newMessageFee) external {
        messageFee = newMessageFee;
    }
}
