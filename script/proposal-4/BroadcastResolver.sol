// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Vm} from "forge-std/Vm.sol";

library BroadcastResolver {
  enum Network {
    Ethereum,
    Polygon,
    BNBChain
  }

  enum Deployed {
    SyntheticNttUni,
    NttManagerImplementation,
    NttManagerProxy,
    WormholeTransceiverImplementation,
    WormholeTransceiverProxy
  }

  function getDeployed(Vm vm, string memory broadcastJson, Network net, Deployed deployed)
    internal
    pure
    returns (address)
  {
    string memory firstTxType =
      vm.parseJsonString(broadcastJson, ".transactions[0].transactionType");

    string memory txIndex;

    if (keccak256(bytes(firstTxType)) == keccak256(bytes("CREATE2"))) {
      // if this is the case, then the external library got deployed, in which case we shift
      // the indices +1.
      //
      // this is bc foundry deploys external libraries first, but they do so deterministically
      // and they check if it's deployed first. if it's deployed already, they always omit the
      // tx. no way around.
      //
      // in our case, for all 3 networks (eth, bnb, pol), the deployment ordering is exactly
      // the same and there is one library per chain.
      if (net == Network.Ethereum) {
        if (deployed == Deployed.SyntheticNttUni) revert();
        if (deployed == Deployed.NttManagerImplementation) txIndex = "1";
        if (deployed == Deployed.NttManagerProxy) txIndex = "2";
        if (deployed == Deployed.WormholeTransceiverImplementation) txIndex = "4";
        if (deployed == Deployed.WormholeTransceiverProxy) txIndex = "5";
      } else {
        if (deployed == Deployed.SyntheticNttUni) txIndex = "1";
        if (deployed == Deployed.NttManagerImplementation) txIndex = "2";
        if (deployed == Deployed.NttManagerProxy) txIndex = "3";
        if (deployed == Deployed.WormholeTransceiverImplementation) txIndex = "5";
        if (deployed == Deployed.WormholeTransceiverProxy) txIndex = "6";
      }
    } else {
      if (net == Network.Ethereum) {
        if (deployed == Deployed.SyntheticNttUni) revert();
        if (deployed == Deployed.NttManagerImplementation) txIndex = "0";
        if (deployed == Deployed.NttManagerProxy) txIndex = "1";
        if (deployed == Deployed.WormholeTransceiverImplementation) txIndex = "3";
        if (deployed == Deployed.WormholeTransceiverProxy) txIndex = "4";
      } else {
        if (deployed == Deployed.SyntheticNttUni) txIndex = "0";
        if (deployed == Deployed.NttManagerImplementation) txIndex = "1";
        if (deployed == Deployed.NttManagerProxy) txIndex = "2";
        if (deployed == Deployed.WormholeTransceiverImplementation) txIndex = "4";
        if (deployed == Deployed.WormholeTransceiverProxy) txIndex = "5";
      }
    }

    return vm.parseJsonAddress(
      broadcastJson, string.concat(".transactions[", txIndex, "].contractAddress")
    );
  }
}
