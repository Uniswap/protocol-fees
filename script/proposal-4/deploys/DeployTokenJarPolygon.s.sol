// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import {TokenJar} from "../../../src/TokenJar.sol";
import {V3OpenFeeAdapter} from "../../../src/feeAdapters/V3OpenFeeAdapter.sol";

import "../Constants.sol" as Constants;

uint256 constant CHAIN_ID = 0x00;
address constant OWNER = Constants.Polygon.FX_CHILD;
address constant UNI_TOKEN = address(0x00);
bytes32 constant SALT = bytes32(uint256(0x67));

// Protocol fee defaults — same as mainnet
uint8 constant DEFAULT_FEE_100 = (4 << 4) | 4; // 1/4 for 0.01% tier
uint8 constant DEFAULT_FEE_500 = (4 << 4) | 4; // 1/4 for 0.05% tier
uint8 constant DEFAULT_FEE_3000 = (6 << 4) | 6; // 1/6 for 0.30% tier
uint8 constant DEFAULT_FEE_10000 = (6 << 4) | 6; // 1/6 for 1.00% tier

contract DeployTokenJarPolygon is Script {
    TokenJar internal tokenJar;
    V3OpenFeeAdapter internal v3OpenFeeAdapter;
    address internal releaser_PLACEHOLDER;

    function run() public {
        require(CHAIN_ID != 0, "CHAIN_ID is zero");
        require(CHAIN_ID == block.chainid, "CHAIN_ID mismatch");
        require(OWNER != address(0x00), "OWNER is zero");
        require(UNI_TOKEN != address(0x00), "UNI_TOKEN is zero");

        console2.log("=== Polygon Deployment ===");
        vm.startBroadcast();

        // -----------------------------------------------------------------------------------------
        // Transaction 01
        //
        // Deploy token jar.
        tokenJar = new TokenJar{salt: SALT}();

        // -----------------------------------------------------------------------------------------
        // Transaction 02
        //
        // Set token jar releaser.
        tokenJar.setReleaser(releaser_PLACEHOLDER);

        // -----------------------------------------------------------------------------------------
        // Transaction 03
        //
        // Transfer token jar ownership to bridge (owner).
        tokenJar.transferOwnership(OWNER);

        // -----------------------------------------------------------------------------------------
        // Transaction 04
        //
        // Set threshold setter on releaser.
        // releaser.setThresholdSetter(OWNER);

        // -----------------------------------------------------------------------------------------
        // Transaction 05
        //
        // Transfer ownership of releaser.
        // releaser.transferOwnership(OWNER);

        // -----------------------------------------------------------------------------------------
        // Transaction 06
        //
        // Deploy V3 fee adapter
        v3OpenFeeAdapter = new V3OpenFeeAdapter{salt: SALT}(
            Constants.Polygon.V3_FACTORY,
            address(tokenJar)
        );

        // -----------------------------------------------------------------------------------------
        // Transaction 07
        //
        // Set fee setter to self
        v3OpenFeeAdapter.setFeeSetter(address(this));

        // -----------------------------------------------------------------------------------------
        // Transaction 08
        //
        // Set default fee (applied when no tier or pool override is set).
        v3OpenFeeAdapter.setDefaultFee(DEFAULT_FEE_100);

        // -----------------------------------------------------------------------------------------
        // Transaction 09, 10, 11, 12
        //
        // Set fee tier defaults
        v3OpenFeeAdapter.setFeeTierDefault(100, DEFAULT_FEE_100);
        v3OpenFeeAdapter.setFeeTierDefault(500, DEFAULT_FEE_500);
        v3OpenFeeAdapter.setFeeTierDefault(3000, DEFAULT_FEE_3000);
        v3OpenFeeAdapter.setFeeTierDefault(10_000, DEFAULT_FEE_10000);

        // -----------------------------------------------------------------------------------------
        // Transaction 13, 14, 15, 16
        //
        // Store fee tiers.
        v3OpenFeeAdapter.storeFeeTier(100);
        v3OpenFeeAdapter.storeFeeTier(500);
        v3OpenFeeAdapter.storeFeeTier(3000);
        v3OpenFeeAdapter.storeFeeTier(10_000);

        // -----------------------------------------------------------------------------------------
        // Transaction 17
        //
        // Transfer fee setter permission to bridge (owner).
        v3OpenFeeAdapter.setFeeSetter(OWNER);

        // -----------------------------------------------------------------------------------------
        // Transaction 18
        //
        // Transfer ownership to bridge (owner).
        v3OpenFeeAdapter.transferOwnership(OWNER);

        vm.stopBroadcast();
    }
}
