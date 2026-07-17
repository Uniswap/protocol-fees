// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {Proposal} from "govkit/types/Proposal.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {Call, LibCall} from "govkit/types/Call.sol";
import {GovernanceSeatbelt} from "govkit/forge/GovernanceSeatbelt.sol";
import {FxRootEncoder} from "govkit/bridges/FxRootEncoder.sol";
import {InboxEncoder} from "govkit/bridges/InboxEncoder.sol";
import {L1CrossDomainMessengerEncoder} from "govkit/bridges/L1CrossDomainMessengerEncoder.sol";
import {OptimismPortal2Encoder} from "govkit/bridges/OptimismPortal2Encoder.sol";
import {WormholeEncoder} from "govkit/bridges/WormholeEncoder.sol";
import {IPoolManager} from "govkit/interfaces/IPoolManager.sol";
import {IL1CrossDomainMessenger} from "govkit/interfaces/bridges/IL1CrossDomainMessenger.sol";

import "../proposal-5/Constants.sol" as Constants;

import {DESCRIPTION} from "./Description.sol";

contract V4FeeProposal is Script {
  Recorder internal recorder;
  Uniswap internal uniswap;

  function run() public {
    vm.createDir("./out/.seatbelt/", true);
    recorder.initialize("DeployV4FeeInfra");
    uniswap.loadLatest();
    {
      // ---------------------------------------------------------------------------------------------
      // 00: Activate V4 Fees for Ethereum.
      //
      Call memory activateV4FeesEthereum = Call({
        target: uniswap.ethereum.poolManager,
        value: 0,
        data: abi.encodeCall(
          IPoolManager.setProtocolFeeController, (recorder.read(ChainId.Ethereum, "V4FeeAdapter"))
        )
      });

      // ---------------------------------------------------------------------------------------------
      // 01: Activate V4 Fees for Arbitrum.
      //
      Call memory activateV4FeesArbitrum = InboxEncoder.encode({
        inbox: uniswap.ethereum.bridge.arbitrum,
        timelock: uniswap.ethereum.timelock,
        remoteCall: Call({
          target: uniswap.arbitrum.poolManager,
          value: 0,
          data: abi.encodeCall(
            IPoolManager.setProtocolFeeController, (recorder.read(ChainId.Arbitrum, "V4FeeAdapter"))
          )
        })
      });

      // ---------------------------------------------------------------------------------------------
      // 02: Activate V4 Fees for Base.
      //
      Call memory activateV4FeesBase = L1CrossDomainMessengerEncoder.encode({
        l1CrossDomainMessenger: uniswap.ethereum.bridge.base,
        crossChainAccount: uniswap.base.crossChainAccount,
        remoteCall: Call({
          target: uniswap.base.poolManager,
          value: 0,
          data: abi.encodeCall(
            IPoolManager.setProtocolFeeController, (recorder.read(ChainId.Base, "V4FeeAdapter"))
          )
        })
      });

      // ---------------------------------------------------------------------------------------------
      // 03: Activate V4 Fees for BNB Chain.
      //
      Call memory activateV4FeesBNBChain = WormholeEncoder.encode({
        sourceSender: uniswap.ethereum.bridge.bnbChain,
        remoteReceiver: uniswap.bnbChain.wormholeReceiver,
        chainId: ChainId.BNBChain,
        value: 0,
        remoteCalls: LibCall.newCalls(
          [Call({
              target: uniswap.bnbChain.poolManager,
              value: 0,
              data: abi.encodeCall(
                IPoolManager.setProtocolFeeController,
                (recorder.read(ChainId.BNBChain, "V4FeeAdapter"))
              )
            })]
        )
      });

      // ---------------------------------------------------------------------------------------------
      // 04: Activate V4 Fees for Celo.
      //
      Call memory activateV4FeesCelo = L1CrossDomainMessengerEncoder.encode({
        l1CrossDomainMessenger: uniswap.ethereum.bridge.celo,
        crossChainAccount: uniswap.celo.crossChainAccount,
        remoteCall: Call({
          target: uniswap.celo.poolManager,
          value: 0,
          data: abi.encodeCall(
            IPoolManager.setProtocolFeeController, (recorder.read(ChainId.Celo, "V4FeeAdapter"))
          )
        })
      });

      // ---------------------------------------------------------------------------------------------
      // 05: Activate V4 Fees for Optimism
      //
      Call memory activateV4FeesOPMainnet = L1CrossDomainMessengerEncoder.encode({
        l1CrossDomainMessenger: uniswap.ethereum.bridge.optimism,
        crossChainAccount: uniswap.optimism.crossChainAccount,
        remoteCall: Call({
          target: uniswap.optimism.poolManager,
          value: 0,
          data: abi.encodeCall(
            IPoolManager.setProtocolFeeController, (recorder.read(ChainId.Optimism, "V4FeeAdapter"))
          )
        })
      });

      // ---------------------------------------------------------------------------------------------
      // 06: Activate V4 Fees for Robinhood
      //
      Call memory activateV4FeesRobinhood = InboxEncoder.encode({
        inbox: Constants.Ethereum.RH_INBOX,
        timelock: uniswap.ethereum.timelock,
        remoteCall: Call({
          target: Constants.Robinhood.POOL_MANAGER,
          value: 0,
          data: abi.encodeCall(
            IPoolManager.setProtocolFeeController,
            (recorder.read(Constants.Robinhood.CHAIN_ID, "V4FeeAdapter"))
          )
        })
      });

      Proposal memory v4FeeActivationProposalPartOne = Proposal({
        description: string.concat("# Activate v4 Protocol Fees (Part 1/2) \n\n", DESCRIPTION),
        calls: LibCall.newCalls(
          [
            activateV4FeesEthereum,
            activateV4FeesArbitrum,
            activateV4FeesBase,
            activateV4FeesBNBChain,
            activateV4FeesCelo,
            activateV4FeesOPMainnet,
            activateV4FeesRobinhood
          ]
        )
      });

      vm.writeFile({
        path: "./out/.seatbelt/V4FeeActivationProposalPartOne.json",
        data: GovernanceSeatbelt.toJson({
          proposal: v4FeeActivationProposalPartOne, governorBravo: uniswap.ethereum.governorBravo
        })
      });
    }
    {
      // ---------------------------------------------------------------------------------------------
      // 00: Activate V4 Fees for Polygon.
      //
      Call memory activateV4FeesPolygon = FxRootEncoder.encode({
        fxRoot: uniswap.ethereum.bridge.polygon,
        fxReceiver: uniswap.polygon.fxReceiver,
        remoteCalls: LibCall.newCalls(
          [Call({
              target: uniswap.polygon.poolManager,
              value: 0,
              data: abi.encodeCall(
                IPoolManager.setProtocolFeeController,
                (recorder.read(ChainId.Polygon, "V4FeeAdapter"))
              )
            })]
        )
      });

      // ---------------------------------------------------------------------------------------------
      // 01: Activate V4 Fees for Soneium.
      //
      Call memory activateV4FeesSoneium = L1CrossDomainMessengerEncoder.encode({
        l1CrossDomainMessenger: uniswap.ethereum.bridge.soneium,
        crossChainAccount: uniswap.soneium.crossChainAccount,
        remoteCall: Call({
          target: uniswap.soneium.poolManager,
          value: 0,
          data: abi.encodeCall(
            IPoolManager.setProtocolFeeController, (recorder.read(ChainId.Soneium, "V4FeeAdapter"))
          )
        })
      });

      // ---------------------------------------------------------------------------------------------
      // 02: Activate V4 Fees for Worldchain.
      //
      Call memory activateV4FeesWorldchain = OptimismPortal2Encoder.encode({
        portal: IL1CrossDomainMessenger(uniswap.ethereum.bridge.worldChain).portal(),
        remoteCall: Call({
          target: uniswap.worldChain.poolManager,
          value: 0,
          data: abi.encodeCall(
            IPoolManager.setProtocolFeeController,
            (recorder.read(ChainId.WorldChain, "V4FeeAdapter"))
          )
        })
      });

      // ---------------------------------------------------------------------------------------------
      // 03: Activate V4 Fees for X Layer
      //
      Call memory activateV4FeesXLayer = OptimismPortal2Encoder.encode({
        portal: IL1CrossDomainMessenger(uniswap.ethereum.bridge.xLayer).portal(),
        remoteCall: Call({
          target: uniswap.xLayer.poolManager,
          value: 0,
          data: abi.encodeCall(
            IPoolManager.setProtocolFeeController, (recorder.read(ChainId.XLayer, "V4FeeAdapter"))
          )
        })
      });

      // ---------------------------------------------------------------------------------------------
      // 04: Activate V4 Fees for Zora.
      //
      Call memory activateV4FeesZora = L1CrossDomainMessengerEncoder.encode({
        l1CrossDomainMessenger: uniswap.ethereum.bridge.zora,
        crossChainAccount: uniswap.zora.crossChainAccount,
        remoteCall: Call({
          target: uniswap.zora.poolManager,
          value: 0,
          data: abi.encodeCall(
            IPoolManager.setProtocolFeeController, (recorder.read(ChainId.Zora, "V4FeeAdapter"))
          )
        })
      });

      Proposal memory v4FeeActivationProposalPartTwo = Proposal({
        description: string.concat("# Activate v4 Protocol Fees (Part 2/2) \n\n", DESCRIPTION),
        calls: LibCall.newCalls(
          [
            activateV4FeesPolygon,
            activateV4FeesSoneium,
            activateV4FeesWorldchain,
            activateV4FeesXLayer,
            activateV4FeesZora
          ]
        )
      });

      vm.writeFile({
        path: "./out/.seatbelt/V4FeeActivationProposalPartTwo.json",
        data: GovernanceSeatbelt.toJson({
          proposal: v4FeeActivationProposalPartTwo, governorBravo: uniswap.ethereum.governorBravo
        })
      });
    }
  }
}
