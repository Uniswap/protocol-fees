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
import {
  BroadcastResolver,
  DeployWormholeInfraBroadcast,
  DeployAndConfigureWormohleInfraBroadcast
} from "../../../script/proposal-4/BroadcastResolver.sol";
import {IV3OpenFeeAdapter} from "../../../src/interfaces/IV3OpenFeeAdapter.sol";
import {ITokenJar} from "../../../src/interfaces/ITokenJar.sol";
import {IReleaser} from "../../../src/interfaces/IReleaser.sol";

import {
  NttManagerNoRateLimiting
} from "lib/native-token-transfers/evm/src/NttManager/NttManagerNoRateLimiting.sol";
import {IManagerBase} from "lib/native-token-transfers/evm/src/interfaces/IManagerBase.sol";
import {
  WormholeTransceiver
} from "lib/native-token-transfers/evm/src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";

string constant BNB_DEPLOY_PATH = "broadcast/DeployWormholeInfraBNBChain.s.sol/56/run-latest.json";
string constant POLYGON_DEPLOY_PATH =
  "broadcast/DeployWormholeInfraPolygon.s.sol/137/run-latest.json";
string constant ETH_DEPLOY_PATH = "broadcast/DeployWormholeInfraEthereum.s.sol/1/run-latest.json";

string constant BNB_DEPLOY_FEE_INFRA_PATH =
  "broadcast/DeployAndConfigureFeeInfraBNBChain.s.sol/56/run-latest.json";
string constant POLYGON_DEPLOY_FEE_INFRA_PATH =
  "broadcast/DeployAndConfigureFeeInfraPolygon.s.sol/137/run-latest.json";

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
  State internal state;

  function setUp() public {
    bool shouldRun = vm.envOr("PROP4_POSTFLIGHT", false);
    vm.skip(!shouldRun);

    _loadDeployments();
  }

  function testProtocolState() public {
    uint256 celoFork = vm.createFork(vm.rpcUrl("fork_celo"));
    uint256 bnbChainFork = vm.createFork(vm.rpcUrl("fork_bnb_chain"));
    uint256 polygonFork = vm.createFork(vm.rpcUrl("fork_polygon"));

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
    // -- simulate prop outcomes
    //

    // Celo
    vm.selectFork(celoFork);
    vm.startPrank(Constants.Celo.UNISWAP_WORMHOLE_MESSAGE_RECEIVER);
    {
      IUniswapV2Factory(Constants.Celo.V2_FACTORY).setFeeTo(Constants.Celo.TOKEN_JAR);

      IUniswapV2Factory(Constants.Celo.V2_FACTORY)
        .setFeeToSetter(Constants.Celo.CROSS_CHAIN_ACCOUNT);

      IUniswapV3Factory(Constants.Celo.V3_FACTORY).setOwner(Constants.Celo.V3_OPEN_FEE_ADAPTER);

      IUniswapV4PoolManager(Constants.Celo.V4_POOL_MANAGER)
        .transferOwnership(Constants.Celo.CROSS_CHAIN_ACCOUNT);
    }
    vm.stopPrank();

    // BNB Chain
    vm.selectFork(bnbChainFork);
    vm.startPrank(Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER);
    {
      IUniswapV2Factory(Constants.BNB.V2_FACTORY).setFeeTo(state.bnbChain.tokenJar);
      IUniswapV3Factory(Constants.BNB.V3_FACTORY).setOwner(state.bnbChain.v3OpenFeeAdapter);
    }
    vm.stopPrank();

    // Polygon
    vm.selectFork(polygonFork);
    vm.startPrank(Constants.Polygon.ETHEREUM_PROXY);
    {
      IUniswapV2Factory(Constants.Polygon.V2_FACTORY).setFeeTo(state.polygon.tokenJar);
      IUniswapV3Factory(Constants.Polygon.V3_FACTORY).setOwner(state.polygon.v3OpenFeeAdapter);
    }
    vm.stopPrank();

    // -----------------------------------------------------------------------------------------
    // -- celo protocol state check
    //
    vm.selectFork(celoFork);

    // Core
    //
    assertEq(IUniswapV2Factory(Constants.Celo.V2_FACTORY).feeTo(), Constants.Celo.TOKEN_JAR);
    assertEq(
      IUniswapV2Factory(Constants.Celo.V2_FACTORY).feeToSetter(), Constants.Celo.CROSS_CHAIN_ACCOUNT
    );
    assertEq(
      IUniswapV3Factory(Constants.Celo.V3_FACTORY).owner(), Constants.Celo.V3_OPEN_FEE_ADAPTER
    );
    assertEq(
      IUniswapV4PoolManager(Constants.Celo.V4_POOL_MANAGER).owner(),
      Constants.Celo.CROSS_CHAIN_ACCOUNT
    );

    // Fee Infrastructure
    assertEq(IOwned(Constants.Celo.TOKEN_JAR).owner(), Constants.Celo.CROSS_CHAIN_ACCOUNT);
    assertEq(IOwned(Constants.Celo.V3_OPEN_FEE_ADAPTER).owner(), Constants.Celo.CROSS_CHAIN_ACCOUNT);
    assertEq(
      IV3OpenFeeAdapter(Constants.Celo.V3_OPEN_FEE_ADAPTER).feeSetter(),
      Constants.Celo.CROSS_CHAIN_ACCOUNT
    );

    // -----------------------------------------------------------------------------------------
    // -- bnb chain protocol state check
    //
    vm.selectFork(bnbChainFork);

    // Core
    assertEq(IUniswapV2Factory(Constants.BNB.V2_FACTORY).feeTo(), state.bnbChain.tokenJar);
    assertEq(
      IUniswapV2Factory(Constants.BNB.V2_FACTORY).feeToSetter(),
      Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
    );
    assertEq(IUniswapV3Factory(Constants.BNB.V3_FACTORY).owner(), state.bnbChain.v3OpenFeeAdapter);
    assertEq(
      IUniswapV4PoolManager(Constants.BNB.V4_POOL_MANAGER).owner(),
      Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
    );

    // Wormhole Infrastructure
    {
      NttManagerNoRateLimiting.TransceiverInfo[] memory transceiverInfos =
        NttManagerNoRateLimiting(state.bnbChain.nttManager).getTransceiverInfo();
      assertEq(transceiverInfos.length, 1);
      assertEq(transceiverInfos[0].registered, true);
      assertEq(transceiverInfos[0].enabled, true);
      assertEq(transceiverInfos[0].index, 0);

      assertEq(
        NttManagerNoRateLimiting(state.bnbChain.nttManager).getMode(),
        uint8(IManagerBase.Mode.BURNING)
      );
      assertEq(
        NttManagerNoRateLimiting(state.bnbChain.nttManager).token(), state.bnbChain.syntheticNttUni
      );
      assertEq(NttManagerNoRateLimiting(state.bnbChain.nttManager).getThreshold(), 1);
      assertEq(
        WormholeTransceiver(state.bnbChain.wormholeTransceiver).nttManager(),
        state.bnbChain.nttManager
      );
      assertEq(
        WormholeTransceiver(state.bnbChain.wormholeTransceiver).nttManagerToken(),
        state.bnbChain.syntheticNttUni
      );
      assertEq(WormholeTransceiver(state.bnbChain.wormholeTransceiver).consistencyLevel(), 202);
      assertEq(WormholeTransceiver(state.bnbChain.wormholeTransceiver).customConsistencyLevel(), 0);
      assertEq(WormholeTransceiver(state.bnbChain.wormholeTransceiver).additionalBlocks(), 0);
      assertEq(
        WormholeTransceiver(state.bnbChain.wormholeTransceiver).customConsistencyLevelAddress(),
        address(0x00)
      );
      assertEq(
        address(WormholeTransceiver(state.bnbChain.wormholeTransceiver).wormhole()),
        Constants.BNB.WORMHOLE
      );

      address bnbChainTransceiverPeer = b32Addr(
        WormholeTransceiver(state.bnbChain.wormholeTransceiver)
          .getWormholePeer(Constants.Wormhole.ETH_CHAIN_ID)
      );
      NttManagerNoRateLimiting.NttManagerPeer memory bnbChainNttManagerPeer = NttManagerNoRateLimiting(
          state.bnbChain.nttManager
        ).getPeer(Constants.Wormhole.ETH_CHAIN_ID);

      assertEq(bnbChainTransceiverPeer, state.ethereum.wormholeTransceiver);
      assertEq(b32Addr(bnbChainNttManagerPeer.peerAddress), state.ethereum.nttManager);
      assertEq(bnbChainNttManagerPeer.tokenDecimals, 18);
      assertEq(
        WormholeTransceiver(state.bnbChain.wormholeTransceiver).owner(),
        Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
      );
      assertEq(WormholeTransceiver(state.bnbChain.wormholeTransceiver).pauser(), address(0x00));
      assertEq(
        NttManagerNoRateLimiting(state.bnbChain.nttManager).owner(),
        Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
      );
      assertEq(NttManagerNoRateLimiting(state.bnbChain.nttManager).pauser(), address(0x00));
    }

    // Fee Infrastructure
    {
      assertEq(ITokenJar(state.bnbChain.tokenJar).releaser(), state.bnbChain.wormholeReleaser);
      assertEq(
        IOwned(state.bnbChain.tokenJar).owner(), Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
      );
      assertEq(
        IReleaser(state.bnbChain.wormholeReleaser).thresholdSetter(),
        Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
      );
      assertEq(
        IOwned(state.bnbChain.wormholeReleaser).owner(),
        Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
      );
      assertEq(
        IV3OpenFeeAdapter(state.bnbChain.v3OpenFeeAdapter).feeSetter(),
        Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
      );
      assertEq(
        IOwned(state.bnbChain.v3OpenFeeAdapter).owner(),
        Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER
      );
      assertEq(
        IV3OpenFeeAdapter(state.bnbChain.v3OpenFeeAdapter).TOKEN_JAR(), state.bnbChain.tokenJar
      );
    }

    // -----------------------------------------------------------------------------------------
    // -- polygon protocol state check
    //
    vm.selectFork(polygonFork);

    // Core
    assertEq(IUniswapV2Factory(Constants.Polygon.V2_FACTORY).feeTo(), state.polygon.tokenJar);
    assertEq(
      IUniswapV2Factory(Constants.Polygon.V2_FACTORY).feeToSetter(),
      Constants.Polygon.ETHEREUM_PROXY
    );
    assertEq(
      IUniswapV3Factory(Constants.Polygon.V3_FACTORY).owner(), state.polygon.v3OpenFeeAdapter
    );
    assertEq(
      IUniswapV4PoolManager(Constants.Polygon.V4_POOL_MANAGER).owner(),
      Constants.Polygon.ETHEREUM_PROXY
    );

    // Wormhole Infrastructure
    {
      NttManagerNoRateLimiting.TransceiverInfo[] memory transceiverInfos =
        NttManagerNoRateLimiting(state.polygon.nttManager).getTransceiverInfo();
      assertEq(transceiverInfos.length, 1);
      assertEq(transceiverInfos[0].registered, true);
      assertEq(transceiverInfos[0].enabled, true);
      assertEq(transceiverInfos[0].index, 0);

      assertEq(
        NttManagerNoRateLimiting(state.polygon.nttManager).getMode(),
        uint8(IManagerBase.Mode.BURNING)
      );
      assertEq(
        NttManagerNoRateLimiting(state.polygon.nttManager).token(), state.polygon.syntheticNttUni
      );
      assertEq(NttManagerNoRateLimiting(state.polygon.nttManager).getThreshold(), 1);
      assertEq(
        WormholeTransceiver(state.polygon.wormholeTransceiver).nttManager(),
        state.polygon.nttManager
      );
      assertEq(
        WormholeTransceiver(state.polygon.wormholeTransceiver).nttManagerToken(),
        state.polygon.syntheticNttUni
      );
      assertEq(WormholeTransceiver(state.polygon.wormholeTransceiver).consistencyLevel(), 202);
      assertEq(WormholeTransceiver(state.polygon.wormholeTransceiver).customConsistencyLevel(), 0);
      assertEq(WormholeTransceiver(state.polygon.wormholeTransceiver).additionalBlocks(), 0);
      assertEq(
        WormholeTransceiver(state.polygon.wormholeTransceiver).customConsistencyLevelAddress(),
        address(0x00)
      );
      assertEq(
        address(WormholeTransceiver(state.polygon.wormholeTransceiver).wormhole()),
        Constants.Polygon.WORMHOLE
      );

      address polygonChainTransceiverPeer = b32Addr(
        WormholeTransceiver(state.polygon.wormholeTransceiver)
          .getWormholePeer(Constants.Wormhole.ETH_CHAIN_ID)
      );
      NttManagerNoRateLimiting.NttManagerPeer memory polygonChainNttManagerPeer =
        NttManagerNoRateLimiting(state.polygon.nttManager).getPeer(Constants.Wormhole.ETH_CHAIN_ID);

      assertEq(polygonChainTransceiverPeer, state.ethereum.wormholeTransceiver);
      assertEq(b32Addr(polygonChainNttManagerPeer.peerAddress), state.ethereum.nttManager);
      assertEq(polygonChainNttManagerPeer.tokenDecimals, 18);
      assertEq(
        WormholeTransceiver(state.polygon.wormholeTransceiver).owner(),
        Constants.Polygon.ETHEREUM_PROXY
      );
      assertEq(WormholeTransceiver(state.polygon.wormholeTransceiver).pauser(), address(0x00));
      assertEq(
        NttManagerNoRateLimiting(state.polygon.nttManager).owner(), Constants.Polygon.ETHEREUM_PROXY
      );
      assertEq(NttManagerNoRateLimiting(state.polygon.nttManager).pauser(), address(0x00));
    }

    // Fee Infrastructure
    {
      assertEq(ITokenJar(state.polygon.tokenJar).releaser(), state.polygon.wormholeReleaser);
      assertEq(IOwned(state.polygon.tokenJar).owner(), Constants.Polygon.ETHEREUM_PROXY);
      assertEq(
        IReleaser(state.polygon.wormholeReleaser).thresholdSetter(),
        Constants.Polygon.ETHEREUM_PROXY
      );
      assertEq(IOwned(state.polygon.wormholeReleaser).owner(), Constants.Polygon.ETHEREUM_PROXY);
      assertEq(
        IV3OpenFeeAdapter(state.polygon.v3OpenFeeAdapter).feeSetter(),
        Constants.Polygon.ETHEREUM_PROXY
      );
      assertEq(IOwned(state.polygon.v3OpenFeeAdapter).owner(), Constants.Polygon.ETHEREUM_PROXY);
      assertEq(
        IV3OpenFeeAdapter(state.polygon.v3OpenFeeAdapter).TOKEN_JAR(), state.polygon.tokenJar
      );
    }
  }

  function _loadDeployments() internal {
    /// forge-lint: disable-next-line(unsafe-cheatcode)
    string memory bnbChainDeployJson = vm.readFile(BNB_DEPLOY_PATH);

    DeployWormholeInfraBroadcast memory bnbInfra = BroadcastResolver.getDeployWormholeInfra({
      vm: vm, broadcastJson: bnbChainDeployJson, network: BroadcastResolver.Network.BNBChain
    });

    state.bnbChain.syntheticNttUni = bnbInfra.syntheticNttUni;
    state.bnbChain.nttManager = bnbInfra.nttManagerProxy;
    state.bnbChain.wormholeTransceiver = bnbInfra.wormholeTransceiverProxy;

    /// forge-lint: disable-next-line(unsafe-cheatcode)
    string memory bnbChainDeployFeeInfraJson = vm.readFile(BNB_DEPLOY_FEE_INFRA_PATH);

    DeployAndConfigureWormohleInfraBroadcast memory bnbFeeInfra =
      BroadcastResolver.getDeployAndConfigureWormholeInfra({
        vm: vm,
        broadcastJson: bnbChainDeployFeeInfraJson,
        network: BroadcastResolver.Network.BNBChain
      });

    state.bnbChain.tokenJar = bnbFeeInfra.tokenJar;
    state.bnbChain.wormholeReleaser = bnbFeeInfra.releaser;
    state.bnbChain.v3OpenFeeAdapter = bnbFeeInfra.v3OpenFeeAdapter;

    /// forge-lint: disable-next-line(unsafe-cheatcode)
    string memory polygonDeployJson = vm.readFile(POLYGON_DEPLOY_PATH);

    DeployWormholeInfraBroadcast memory polygonInfra = BroadcastResolver.getDeployWormholeInfra({
      vm: vm, broadcastJson: polygonDeployJson, network: BroadcastResolver.Network.Polygon
    });

    state.polygon.syntheticNttUni = polygonInfra.syntheticNttUni;
    state.polygon.nttManager = polygonInfra.nttManagerProxy;
    state.polygon.wormholeTransceiver = polygonInfra.wormholeTransceiverProxy;

    /// forge-lint: disable-next-line(unsafe-cheatcode)
    string memory polygonDeployFeeInfraJson = vm.readFile(POLYGON_DEPLOY_FEE_INFRA_PATH);

    DeployAndConfigureWormohleInfraBroadcast memory polygonFeeInfra =
      BroadcastResolver.getDeployAndConfigureWormholeInfra({
        vm: vm, broadcastJson: polygonDeployFeeInfraJson, network: BroadcastResolver.Network.Polygon
      });

    state.polygon.tokenJar = polygonFeeInfra.tokenJar;
    state.polygon.wormholeReleaser = polygonFeeInfra.releaser;
    state.polygon.v3OpenFeeAdapter = polygonFeeInfra.v3OpenFeeAdapter;

    /// forge-lint: disable-next-line(unsafe-cheatcode)
    string memory ethereumDeployJson = vm.readFile(ETH_DEPLOY_PATH);

    DeployWormholeInfraBroadcast memory ethInfra = BroadcastResolver.getDeployWormholeInfra({
      vm: vm, broadcastJson: ethereumDeployJson, network: BroadcastResolver.Network.Ethereum
    });

    state.ethereum.nttManager = ethInfra.nttManagerProxy;
    state.ethereum.wormholeTransceiver = ethInfra.wormholeTransceiverProxy;
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
