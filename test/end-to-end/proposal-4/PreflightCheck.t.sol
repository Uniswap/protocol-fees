// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";

import "../../../script/proposal-4/Constants.sol" as Constants;
import {
    IUniswapV2Factory,
    IUniswapV3Factory,
    IUniswapV4PoolManager,
    IOwned
} from "../../../script/proposal-4/Interfaces.sol";
import {IV3OpenFeeAdapter} from "../../../src/interfaces/IV3OpenFeeAdapter.sol";

contract PreflightCheckTest is Test {
    function __testProtocolState() public {

        // -----------------------------------------------------------------------------------------
        // -- celo protocol state check
        //
        vm.createSelectFork("fork_celo");

        // Core
        //
        assertEq(
            IUniswapV2Factory(Constants.Celo.V2_FACTORY).feeTo(),
            address(0x00)
        );
        assertEq(
            IUniswapV2Factory(Constants.Celo.V2_FACTORY).feeToSetter(),
            Constants.Celo.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
        );
        assertEq(
            IUniswapV3Factory(Constants.Celo.V3_FACTORY).owner(),
            Constants.Celo.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
        );
        assertEq(
            IUniswapV4PoolManager(Constants.Celo.V4_POOL_MANAGER).owner(),
            Constants.Celo.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
        );

        // Fee Infrastructure
        assertEq(
            IOwned(Constants.Celo.TOKEN_JAR).owner(),
            Constants.Celo.CROSS_CHAIN_ACCOUNT
        );
        assertEq(
            IOwned(Constants.Celo.V3_OPEN_FEE_ADAPTER).owner(),
            Constants.Celo.CROSS_CHAIN_ACCOUNT
        );
        assertEq(
            IV3OpenFeeAdapter(Constants.Celo.V3_OPEN_FEE_ADAPTER).feeSetter(),
            Constants.Celo.CROSS_CHAIN_ACCOUNT
        );

        // -----------------------------------------------------------------------------------------
        // -- bnb chain protocol state check
        //
        vm.createSelectFork("fork_bnb_chain");

        // Core
        //
        assertEq(
            IUniswapV2Factory(Constants.BNB.V2_FACTORY).feeTo(),
            address(0x00)
        );
        assertEq(
            IUniswapV2Factory(Constants.BNB.V2_FACTORY).feeToSetter(),
            Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
        );
        assertEq(
            IUniswapV3Factory(Constants.BNB.V3_FACTORY).owner(),
            Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
        );

        // -----------------------------------------------------------------------------------------
        // -- polygon protocol state check
        //
        vm.createSelectFork("fork_polygon");

        // Core
        //
        assertEq(
            IUniswapV2Factory(Constants.Polygon.V2_FACTORY).feeTo(),
            address(0x00)
        );
        assertEq(
            IUniswapV2Factory(Constants.Polygon.V2_FACTORY).feeToSetter(),
            Constants.Polygon.ETHEREUM_PROXY
        );
        assertEq(
            IUniswapV3Factory(Constants.Polygon.V3_FACTORY).owner(),
            Constants.Polygon.ETHEREUM_PROXY
        );
    }
}
