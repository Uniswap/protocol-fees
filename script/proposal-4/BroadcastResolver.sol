// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Vm} from "forge-std/Vm.sol";

struct DeployWormholeInfraBroadcast {
  address syntheticNttUni;
  address nttManagerImplementation;
  address nttManagerProxy;
  address wormholeTransceiverImplementation;
  address wormholeTransceiverProxy;
}

struct DeployAndConfigureWormohleInfraBroadcast {
  address tokenJar;
  address releaser;
  address v3OpenFeeAdapter;
}

library BroadcastResolver {
  enum Network {
    Ethereum,
    BNBChain,
    Polygon
  }

  function getDeployWormholeInfra(Vm vm, string memory broadcastJson, Network network)
    external
    pure
    returns (DeployWormholeInfraBroadcast memory)
  {
    string memory firstTxType =
      vm.parseJsonString(broadcastJson, ".transactions[0].transactionType");

    bool externaLibraryWasDeployed = keccak256(bytes(firstTxType)) == keccak256(bytes("CREATE2"));

    if (externaLibraryWasDeployed) {
      if (network == Network.Ethereum) {
        return DeployWormholeInfraBroadcast({
          syntheticNttUni: address(0x00),
          nttManagerImplementation: vm.parseJsonAddress(
            broadcastJson, ".transactions[1].contractAddress"
          ),
          nttManagerProxy: vm.parseJsonAddress(broadcastJson, ".transactions[2].contractAddress"),
          wormholeTransceiverImplementation: vm.parseJsonAddress(
            broadcastJson, ".transactions[4].contractAddress"
          ),
          wormholeTransceiverProxy: vm.parseJsonAddress(
            broadcastJson, ".transactions[5].contractAddress"
          )
        });
      } else {
        return DeployWormholeInfraBroadcast({
          syntheticNttUni: vm.parseJsonAddress(broadcastJson, ".transactions[1].contractAddress"),
          nttManagerImplementation: vm.parseJsonAddress(
            broadcastJson, ".transactions[2].contractAddress"
          ),
          nttManagerProxy: vm.parseJsonAddress(broadcastJson, ".transactions[3].contractAddress"),
          wormholeTransceiverImplementation: vm.parseJsonAddress(
            broadcastJson, ".transactions[5].contractAddress"
          ),
          wormholeTransceiverProxy: vm.parseJsonAddress(
            broadcastJson, ".transactions[6].contractAddress"
          )
        });
      }
    } else {
      if (network == Network.Ethereum) {
        return DeployWormholeInfraBroadcast({
          syntheticNttUni: address(0x00),
          nttManagerImplementation: vm.parseJsonAddress(
            broadcastJson, ".transactions[0].contractAddress"
          ),
          nttManagerProxy: vm.parseJsonAddress(broadcastJson, ".transactions[1].contractAddress"),
          wormholeTransceiverImplementation: vm.parseJsonAddress(
            broadcastJson, ".transactions[3].contractAddress"
          ),
          wormholeTransceiverProxy: vm.parseJsonAddress(
            broadcastJson, ".transactions[4].contractAddress"
          )
        });
      } else {
        return DeployWormholeInfraBroadcast({
          syntheticNttUni: vm.parseJsonAddress(broadcastJson, ".transactions[0].contractAddress"),
          nttManagerImplementation: vm.parseJsonAddress(
            broadcastJson, ".transactions[1].contractAddress"
          ),
          nttManagerProxy: vm.parseJsonAddress(broadcastJson, ".transactions[2].contractAddress"),
          wormholeTransceiverImplementation: vm.parseJsonAddress(
            broadcastJson, ".transactions[4].contractAddress"
          ),
          wormholeTransceiverProxy: vm.parseJsonAddress(
            broadcastJson, ".transactions[5].contractAddress"
          )
        });
      }
    }
  }

  function getDeployAndConfigureWormholeInfra(Vm vm, string memory broadcastJson, Network network)
    external
    pure
    returns (DeployAndConfigureWormohleInfraBroadcast memory)
  {
    require(network != Network.Ethereum, "invalid network");

    return DeployAndConfigureWormohleInfraBroadcast({
      tokenJar: vm.parseJsonAddress(broadcastJson, ".transactions[0].contractAddress"),
      releaser: vm.parseJsonAddress(broadcastJson, ".transactions[1].contractAddress"),
      v3OpenFeeAdapter: vm.parseJsonAddress(broadcastJson, ".transactions[6].contractAddress")
    });
  }
}
