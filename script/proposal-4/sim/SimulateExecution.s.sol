// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";

import "../Constants.sol" as Constants;
import {
    IWormholeSender,
    IUniswapV2Factory,
    IUniswapV3Factory,
    IUniswapV4PoolManager,
    IGovernorBravo,
    IPolygonFxRoot
} from "../Interfaces.sol";

string constant POLYGON_DEPLOY_PATH = "broadcast/DeployAndConfigureFeeInfraPolygon.s.sol/137/run-latest.json";
string constant BNB_DEPLOY_PATH = "broadcast/DeployAndConfigureFeeInfraBNBChain.s.sol/56/run-latest.json";

/// @title Impersonates bridges to simulate proposal run.
contract SimulateExecution is Script {
    function run() external {
        (
            address bnbChainTokenJar,
            address bnbChainOpenV3FeeAdapter,
            address polygonTokenJar,
            address polygonOpenV3FeeAdapter
        ) = _loadDeployments();

        // -----------------------------------------------------------------------------------------
        // -- celo sim
        //
        vm.createSelectFork("celo");

        vm.startPrank(Constants.Celo.CROSS_CHAIN_ACCOUNT);
        IUniswapV2Factory(Constants.Celo.V2_FACTORY).setFeeTo(Constants.Celo.TOKEN_JAR);
        IUniswapV2Factory(Constants.Celo.V2_FACTORY).setFeeToSetter(Constants.Celo.CROSS_CHAIN_ACCOUNT);
        IUniswapV3Factory(Constants.Celo.V3_FACTORY).setOwner(Constants.Celo.V3_OPEN_FEE_ADAPTER);
        IUniswapV4PoolManager(Constants.Celo.V4_POOL_MANAGER).transferOwnership(Constants.Celo.CROSS_CHAIN_ACCOUNT);
        vm.stopPrank();

        // -----------------------------------------------------------------------------------------
        // -- bnb chain sim
        //
        vm.createSelectFork("bnb_chain");

        vm.startPrank(Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER);
        IUniswapV2Factory(Constants.BNB.V2_FACTORY).setFeeTo(bnbChainTokenJar);
        IUniswapV3Factory(Constants.BNB.V3_FACTORY).setOwner(bnbChainOpenV3FeeAdapter);
        vm.stopPrank();

        // -----------------------------------------------------------------------------------------
        // -- polygon sim
        //

        vm.createSelectFork("polygon");
        vm.startPrank(Constants.Polygon.ETHEREUM_PROXY);
        IUniswapV2Factory(Constants.Polygon.V2_FACTORY).setFeeTo(polygonTokenJar);
        IUniswapV3Factory(Constants.Polygon.V3_FACTORY).setOwner(polygonOpenV3FeeAdapter);
        vm.stopPrank();

    }

    function _loadDeployments()
        internal
        view
        returns (
            address bnbChainTokenJar,
            address bnbChainOpenV3FeeAdapter,
            address polygonTokenJar,
            address polygonOpenV3FeeAdapter
        )
    {
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        string memory bnbChainDeployJson = vm.readFile(BNB_DEPLOY_PATH);

        bnbChainTokenJar = vm.parseJsonAddress(
            bnbChainDeployJson,
            ".transactions[0].contractAddress"
        );
        bnbChainOpenV3FeeAdapter = vm.parseJsonAddress(
            bnbChainDeployJson,
            ".transactions[6].contractAddress"
        );

        /// forge-lint: disable-next-line(unsafe-cheatcode)
        string memory polygonDeployJson = vm.readFile(BNB_DEPLOY_PATH);

        polygonTokenJar = vm.parseJsonAddress(
            polygonDeployJson,
            ".transactions[0].contractAddress"
        );
        polygonOpenV3FeeAdapter = vm.parseJsonAddress(
            polygonDeployJson,
            ".transactions[6].contractAddress"
        );

        require(bnbChainTokenJar != address(0x00), "bnbChainTokenJar is address(0x00)");
        require(bnbChainOpenV3FeeAdapter != address(0x00), "bnbChainOpenV3FeeAdapter is address(0x00)");
        require(polygonTokenJar != address(0x00), "polygonTokenJar is address(0x00)");
        require(polygonOpenV3FeeAdapter != address(0x00), "polygonOpenV3FeeAdapter is address(0x00)");
    }
}
