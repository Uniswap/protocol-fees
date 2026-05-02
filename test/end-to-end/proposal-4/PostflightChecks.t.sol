// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";

import "../../../script/proposal-4/Constants.sol" as Constants;
import {
    IWormholeSender,
    IUniswapV2Factory,
    IUniswapV3Factory,
    IUniswapV4PoolManager,
    IGovernorBravo,
    IPolygonFxRoot,
    IOwned
} from "../../../script/proposal-4/Interfaces.sol";
import {IV3OpenFeeAdapter} from "../../../src/interfaces/IV3OpenFeeAdapter.sol";

import {NttManagerNoRateLimiting} from "lib/native-token-transfers/evm/src/NttManager/NttManagerNoRateLimiting.sol";
import {IManagerBase} from "lib/native-token-transfers/evm/src/interfaces/IManagerBase.sol";
import {WormholeTransceiver} from "lib/native-token-transfers/evm/src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";

string constant BNB_DEPLOY_PATH = "broadcast/DeployWormholeInfraBNBChain.s.sol/56/run-latest.json";
string constant POLYGON_DEPLOY_PATH = "broadcast/DeployWormholeInfraPolygon.s.sol/137/run-latest.json";
string constant ETH_DEPLOY_PATH = "broadcast/DeployWormholeInfraEthereum.s.sol/1/run-latest.json";

string constant BNB_DEPLOY_FEE_INFRA_PATH = "broadcast/DeployAndConfigureWormholeInfraBNBChain.s.sol/56/run-latest.json";
string constant POLYGON_DEPLOY_FEE_INFRA_PATH = "broadcast/DeployAndConfigureWormholeInfraPolygon.s.sol/137/run-latest.json";

/// @dev Home chain deployment.
struct LocalDeployment {
    address nttManager;
    address wormholeTransceiver;
}

/// @dev Foreign chain deployment.
struct ExternalDeployment {
    address syntheticNttUni;
    address nttManager;
    address wormholeTransceiver;
    address tokenJar;
    address wormholeReleaser;
    address v3OpenFeeAdapter;
}

struct State {
    LocalDeployment ethereum;
    ExternalDeployment polygon;
    ExternalDeployment bnbChain;
}

contract PostflightCheckTest is Test {
    function testProtocolState() public {
        State memory state = _loadDeployments();

        // -----------------------------------------------------------------------------------------
        // -- loader smoke checks
        //
        
        // Ethereum
        assertNotEq(state.ethereum.nttManager, address(0x00));
        assertNotEq(state.ethereum.wormholeTransceiver, address(0x00));

        // BNB Chain
        assertNotEq(state.bnbChain.syntheticNttUni, address(0x00));
        assertNotEq(state.bnbChain.nttManager, address(0x00));
        assertNotEq(state.bnbChain.wormholeTransceiver, address(0x00));
        assertNotEq(state.bnbChain.tokenJar, address(0x00));
        assertNotEq(state.bnbChain.wormholeReleaser, address(0x00));
        assertNotEq(state.bnbChain.v3OpenFeeAdapter, address(0x00));

        // Polygon
        assertNotEq(state.polygon.syntheticNttUni, address(0x00));
        assertNotEq(state.polygon.nttManager, address(0x00));
        assertNotEq(state.polygon.wormholeTransceiver, address(0x00));
        assertNotEq(state.polygon.tokenJar, address(0x00));
        assertNotEq(state.polygon.wormholeReleaser, address(0x00));
        assertNotEq(state.polygon.v3OpenFeeAdapter, address(0x00));

        // -----------------------------------------------------------------------------------------
        // -- celo protocol state check
        //
        vm.createSelectFork("celo");

        // Core
        //
        assertEq(
            IUniswapV2Factory(Constants.Celo.V2_FACTORY).feeTo(),
            Constants.Celo.TOKEN_JAR
        );
        assertEq(
            IUniswapV2Factory(Constants.Celo.V2_FACTORY).feeToSetter(),
            Constants.Celo.CROSS_CHAIN_ACCOUNT
        );
        assertEq(
            IUniswapV3Factory(Constants.Celo.V3_FACTORY).owner(),
            Constants.Celo.V3_OPEN_FEE_ADAPTER
        );
        assertEq(
            IUniswapV4PoolManager(Constants.Celo.V4_POOL_MANAGER).owner(),
            Constants.Celo.CROSS_CHAIN_ACCOUNT
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
        vm.createSelectFork("bnb_chain");

        // Core
        assertEq(
            IUniswapV2Factory(Constants.BNB.V2_FACTORY).feeTo(),
            state.bnbChain.tokenJar
        );
        assertEq(
            IUniswapV2Factory(Constants.BNB.V2_FACTORY).feeToSetter(),
            Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
        );
        assertEq(
            IUniswapV3Factory(Constants.BNB.V3_FACTORY).owner(),
            state.bnbChain.v3OpenFeeAdapter
        );
        assertEq(
            IUniswapV4PoolManager(Constants.BNB.V4_POOL_MANAGER).owner(),
            Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
        );

        // Wormhole Infrastructure
        NttManagerNoRateLimiting.TransceiverInfo[] memory transceiverInfos =
            NttManagerNoRateLimiting(state.bnbChain.nttManager).getTransceiverInfo();
        assertEq(transceiverInfos.length, 1);
        assertEq(transceiverInfos[0].registered, true);
        assertEq(transceiverInfos[0].enabled, true);
        assertEq(transceiverInfos[0].index, 0);

        require(NttManagerNoRateLimiting(state.bnbChain.nttManager).getMode() == uint8(IManagerBase.Mode.BURNING));
        require(NttManagerNoRateLimiting(state.bnbChain.nttManager).token() == state.bnbChain.syntheticNttUni);
        require(NttManagerNoRateLimiting(state.bnbChain.nttManager).getThreshold() == 1);

        require(WormholeTransceiver(state.bnbChain.wormholeTransceiver).nttManager() == state.bnbChain.nttManager);
        require(WormholeTransceiver(state.bnbChain.wormholeTransceiver).nttManagerToken() == state.bnbChain.syntheticNttUni);
        require(WormholeTransceiver(state.bnbChain.wormholeTransceiver).consistencyLevel() == 202);
        require(WormholeTransceiver(state.bnbChain.wormholeTransceiver).customConsistencyLevel() == 0);
        require(WormholeTransceiver(state.bnbChain.wormholeTransceiver).additionalBlocks() == 0);
        require(WormholeTransceiver(state.bnbChain.wormholeTransceiver).customConsistencyLevelAddress() == address(0x00));
        require(address(WormholeTransceiver(state.bnbChain.wormholeTransceiver).wormhole()) == Constants.BNB.WORMHOLE);

        // Fee Infrastructure
    }

    function _loadDeployments() internal view returns (State memory state) {
        // Transactions: (`BNB_DEPLOY_PATH`)
        //
        // | Index | Action                                                                   |
        // | ----- | ------------------------------------------------------------------------ |
        // | 00    | Deploy `SyntheticNttUni`.                                                |
        // | 01    | Deploy `NttManager` implementation.                                      |
        // | 02    | Deploy `NttManager` proxy.                                               |
        // | 03    | Initialize `NttManager` proxy.                                           |
        // | 04    | Deploy `WormholeTransceiver` implementation.                             |
        // | 05    | Deploy `WormholeTransceiver` proxy.                                      |
        // | 06    | Initialize `WormholeTransceiver` proxy.                                  |
        // | 07    | Set `NttManager` proxy's transceiver to the `WormholeTransceiver` proxy. |
        // | 08    | Set the threshold of transceiver attestation redundancy.                 |
        // | 09    | Set `SyntheticNttUni` mint authority to `NttManager` proxy.              |
        // | 10    | Transfer ownership of `SyntheticNttUni` to governance.                   |
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        string memory bnbChainDeployJson = vm.readFile(BNB_DEPLOY_PATH);

        state.bnbChain.syntheticNttUni = vm.parseJsonAddress(bnbChainDeployJson, ".transactions[0].contractAddress");
        state.bnbChain.nttManager = vm.parseJsonAddress(bnbChainDeployJson, ".transactions[2].contractAddress");
        state.bnbChain.wormholeTransceiver = vm.parseJsonAddress(bnbChainDeployJson, ".transactions[5].contractAddress");

        // Transactions: (`BNB_DEPLOY_FEE_INFRA_PATH`)
        //
        // | Index | Action                                                                                 |
        // | ----- | -------------------------------------------------------------------------------------- |
        // | 00    | Deploy `TokenJar`.                                                                     |
        // | 01    | Deploy `WormholeReleaser`.                                                             |
        // | 02    | Set `WormholeReleaser` as the releaser on `TokenJar`.                                  |
        // | 03    | Transfer `TokenJar` ownership to `UniswapWormholeMessageReceiver`.                     |
        // | 04    | Set `WormholeReleaser` threshold setter to `UniswapWormholeMessageReceiver`.           |
        // | 05    | Transfer ownership of `WormholeReleaser` to `UniswapWormholeMessageReceiver`.          |
        // | 06    | Deploy `V3OpenFeeAdapter`.                                                             |
        // | 07    | Set `V3OpenFeeAdapter` fee setter to the deployer for configuration.                   |
        // | 08    | Set `V3OpenFeeAdapter` default fee.                                                    |
        // | 09    | Set `V3OpenFeeAdapter` fee tier defaults.                                              |
        // | 10    | Set `V3OpenFeeAdapter` fee tier defaults.                                              |
        // | 11    | Set `V3OpenFeeAdapter` fee tier defaults.                                              |
        // | 12    | Set `V3OpenFeeAdapter` fee tier defaults.                                              |
        // | 13    | Store `V3OpenFeeAdapter` fee tiers.                                                    |
        // | 14    | Store `V3OpenFeeAdapter` fee tiers.                                                    |
        // | 15    | Store `V3OpenFeeAdapter` fee tiers.                                                    |
        // | 16    | Store `V3OpenFeeAdapter` fee tiers.                                                    |
        // | 17    | Transfer `V3OpenFeeAdapter` fee setter permission to `UniswapWormholeMessageReceiver`. |
        // | 18    | Transfer `V3OpenFeeAdapter` ownership to `UniswapWormholeMessageReceiver`.             |
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        string memory bnbChainDeployFeeInfraJson = vm.readFile(BNB_DEPLOY_FEE_INFRA_PATH);

        state.bnbChain.tokenJar = vm.parseJsonAddress(bnbChainDeployFeeInfraJson, ".transactions[0].contractAddress");
        state.bnbChain.wormholeReleaser = vm.parseJsonAddress(bnbChainDeployFeeInfraJson, ".transactions[1].contractAddress");
        state.bnbChain.v3OpenFeeAdapter = vm.parseJsonAddress(bnbChainDeployFeeInfraJson, ".transactions[6].contractAddress");

        // Transactions (`POLYGON_DEPLOY_PATH`)
        //
        // | Index | Action                                                                   |
        // | ----- | ------------------------------------------------------------------------ |
        // | 00    | Deploy `SyntheticNttUni`.                                                |
        // | 01    | Deploy `NttManager` implementation.                                      |
        // | 02    | Deploy `NttManager` proxy.                                               |
        // | 03    | Initialize `NttManager` proxy.                                           |
        // | 04    | Deploy `WormholeTransceiver` implementation.                             |
        // | 05    | Deploy `WormholeTransceiver` proxy.                                      |
        // | 06    | Initialize `WormholeTransceiver` proxy.                                  |
        // | 07    | Set `NttManager` proxy's transceiver to the `WormholeTransceiver` proxy. |
        // | 08    | Set the threshold of transceiver attestation redundancy.                 |
        // | 09    | Set `SyntheticNttUni` mint authority to `NttManager` proxy.              |
        // | 10    | Transfer ownership of `SyntheticNttUni` to governance.                   |
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        string memory polygonDeployJson = vm.readFile(POLYGON_DEPLOY_PATH);

        state.polygon.syntheticNttUni = vm.parseJsonAddress(polygonDeployJson, ".transactions[0].contractAddress");
        state.polygon.nttManager = vm.parseJsonAddress(polygonDeployJson, ".transactions[2].contractAddress");
        state.polygon.wormholeTransceiver = vm.parseJsonAddress(polygonDeployJson, ".transactions[5].contractAddress");

        // Transactions (`POLYGON_DEPLOY_FEE_INFRA_PATH`)
        //
        // | Index | Action                                                                                 |
        // | ----- | -------------------------------------------------------------------------------------- |
        // | 00    | Deploy `TokenJar`.                                                                     |
        // | 01    | Deploy `WormholeReleaser`.                                                             |
        // | 02    | Set `WormholeReleaser` as the releaser on `TokenJar`.                                  |
        // | 03    | Transfer `TokenJar` ownership to `UniswapWormholeMessageReceiver`.                     |
        // | 04    | Set `WormholeReleaser` threshold setter to `UniswapWormholeMessageReceiver`.           |
        // | 05    | Transfer ownership of `WormholeReleaser` to `UniswapWormholeMessageReceiver`.          |
        // | 06    | Deploy `V3OpenFeeAdapter`.                                                             |
        // | 07    | Set `V3OpenFeeAdapter` fee setter to the deployer for configuration.                   |
        // | 08    | Set `V3OpenFeeAdapter` default fee.                                                    |
        // | 09    | Set `V3OpenFeeAdapter` fee tier defaults.                                              |
        // | 10    | Set `V3OpenFeeAdapter` fee tier defaults.                                              |
        // | 11    | Set `V3OpenFeeAdapter` fee tier defaults.                                              |
        // | 12    | Set `V3OpenFeeAdapter` fee tier defaults.                                              |
        // | 13    | Store `V3OpenFeeAdapter` fee tiers.                                                    |
        // | 14    | Store `V3OpenFeeAdapter` fee tiers.                                                    |
        // | 15    | Store `V3OpenFeeAdapter` fee tiers.                                                    |
        // | 16    | Store `V3OpenFeeAdapter` fee tiers.                                                    |
        // | 17    | Transfer `V3OpenFeeAdapter` fee setter permission to `UniswapWormholeMessageReceiver`. |
        // | 18    | Transfer `V3OpenFeeAdapter` ownership to `UniswapWormholeMessageReceiver`.             |
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        string memory polygonDeployFeeInfraJson = vm.readFile(POLYGON_DEPLOY_FEE_INFRA_PATH);

        state.polygon.tokenJar = vm.parseJsonAddress(polygonDeployFeeInfraJson, ".transactions[0].contractAddress");
        state.polygon.wormholeReleaser = vm.parseJsonAddress(polygonDeployFeeInfraJson, ".transactions[1].contractAddress");
        state.polygon.v3OpenFeeAdapter = vm.parseJsonAddress(polygonDeployFeeInfraJson, ".transactions[6].contractAddress");


        // Transactions (`ETH_DEPLOY_PATH`)
        //
        // | Index | Action                                                                   |
        // | ----- | ------------------------------------------------------------------------ |
        // | 00    | Deploy `NttManager` implementation.                                      |
        // | 01    | Deploy `NttManager` proxy.                                               |
        // | 02    | Initialize `NttManager` proxy.                                           |
        // | 03    | Deploy `WormholeTransceiver` implementation.                             |
        // | 04    | Deploy `WormholeTransceiver` proxy.                                      |
        // | 05    | Initialize `WormholeTransceiver` proxy.                                  |
        // | 06    | Set `NttManager` proxy's transceiver to the `WormholeTransceiver` proxy. |
        // | 07    | Set the threshold of transceiver attestation redundancy.                 |
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        string memory ethereumDeployJson = vm.readFile(ETH_DEPLOY_PATH);

        state.ethereum.nttManager = vm.parseJsonAddress(ethereumDeployJson, ".transactions[1].contractAddress");
        state.ethereum.wormholeTransceiver = vm.parseJsonAddress(ethereumDeployJson, ".transactions[4].contractAddress");
    }

    function readImplementation(address proxy) internal view returns (address) {
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 value = vm.load(proxy, IMPLEMENTATION_SLOT);

        return address(uint160(uint256(value)));
    }

    function b32Addr(bytes32 b32) internal pure returns (address addr) {
        assembly {
            addr := b32
        }
    }

    function addrB32(address addr) internal pure returns (bytes32 b32) {
        assembly {
            b32 := addr
        }
    }
}
