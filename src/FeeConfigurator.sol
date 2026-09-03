// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Owned} from "solmate/src/auth/Owned.sol";
import {ITokenJar} from "./interfaces/ITokenJar.sol";
import {IReleaser} from "./interfaces/IReleaser.sol";
import {IV3OpenFeeAdapter} from "./interfaces/IV3OpenFeeAdapter.sol";
import {IV4FeeAdapter} from "./interfaces/IV4FeeAdapter.sol";
import {IV4FeePolicy} from "./interfaces/IV4FeePolicy.sol";

contract FeeConfigurator {
    address public releaser;
    address public tokenJar;
    address public v3OpenFeeAdapter;
    address public v4FeeAdapter;
    address public v4FeePolicy;

    // TODO
}
