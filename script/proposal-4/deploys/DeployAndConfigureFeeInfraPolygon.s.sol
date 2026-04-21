// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {TokenJar} from "../../../src/TokenJar.sol";
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

contract DeployAndConfigureFeeInfraPolygonScript is Script {
    // TODO
}
