// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";

import {Uniswap} from "govkit/types/Uniswap.sol";
import {Proposal} from "govkit/types/Proposal.sol";
import {Call, LibCall} from "govkit/types/Call.sol";
import {IUniswapV2Factory} from "govkit/interfaces/IUniswapV2Factory.sol";
import {IUniswapV3Factory} from "govkit/interfaces/IUniswapV3Factory.sol";
import {IPoolManager} from "govkit/interfaces/IPoolManager.sol";
import {GovernanceSeatbelt} from "govkit/forge/GovernanceSeatbelt.sol";
import {OptimismPortal2Encoder} from "govkit/bridges/OptimismPortal2Encoder.sol";

import {DESCRIPTION} from "./Description.sol";
import "./Constants.sol" as Constants;
import {IOmnichainProposalSender} from "./Interfaces.sol";
import {LayerZeroEncoder} from "./LayerZeroEncoder.sol";

function buildMaintenanceProposal(Uniswap storage uniswap) view returns (Proposal memory) {
  return Proposal({
    description: DESCRIPTION,
    calls: LibCall.newCalls(
      [
        // -----------------------------------------------------------------------------------------
        // Action 00:
        //
        // Finalize Layer Zero Configuration for MegaEth
        //
        // Context:
        //
        // The OmnichainGovernanceExecutor is deployed on MegaEth and is configured to receive
        // messages from OmnichainProposalSender on Ethereum. However, the OmnichainProposalSender
        // on Ethereum is not configured to send messages to OmnichainGovernanceExecutor on
        // MegaEth.
        //
        // We set:
        //
        // - `trustedRemoteAddress` on OmnichainProposalSender to the encoded
        //    OmnichainGovernanceExecutor on MegaETH.
        //
        Call({
          target: Constants.Ethereum.OMNICHAIN_PROPOSAL_SENDER,
          value: 0,
          data: abi.encodeCall(
            IOmnichainProposalSender.setTrustedRemoteAddress,
            (
              Constants.LayerZero.MEGA_CHAIN_ID,
              abi.encodePacked(Constants.MegaEth.OMNICHAIN_GOVERNANCE_EXECUTOR)
            )
          )
        }),
        // -----------------------------------------------------------------------------------------
        // Action 01:
        //
        // Transfer Ownership on MegaETH from Layer Zero to Wormhole
        //
        // We set:
        //
        // - `feeToSetter` on the V2 Factory from OmnichainGovernanceExecutor to
        //    UniswapWormholeReceiver.
        // - `owner` on the V3 Factory from OmnichainGovernanceExecutor to
        //    UniswapWormholeReceiver.
        // - `owner` on the V4 Pool Manager from OmnichainGovernanceExecutor to
        //    UniswapWormholeReceiver.
        //
        LayerZeroEncoder.encode({
          omnichainProposalSender: Constants.Ethereum.OMNICHAIN_PROPOSAL_SENDER,
          layerZeroChainId: Constants.LayerZero.MEGA_CHAIN_ID,
          remoteCalls: LibCall.newCalls(
            [
              Call({
                target: uniswap.megaEth.v2Factory,
                value: 0,
                data: abi.encodeCall(
                  IUniswapV2Factory.setFeeToSetter, (Constants.MegaEth.WORMHOLE_RECEIVER)
                )
              }),
              Call({
                target: uniswap.megaEth.v3Factory,
                value: 0,
                data: abi.encodeCall(
                  IUniswapV3Factory.setOwner, (Constants.MegaEth.WORMHOLE_RECEIVER)
                )
              }),
              Call({
                target: uniswap.megaEth.poolManager,
                value: 0,
                data: abi.encodeCall(
                  IPoolManager.transferOwnership, (Constants.MegaEth.WORMHOLE_RECEIVER)
                )
              })
            ]
          )
        }),
        // -----------------------------------------------------------------------------------------
        // Action 02:
        //
        // Transfer Ownership on Avalanche from LayerZero to Wormhole.
        //
        // We set:
        //
        // - `feeToSetter` on the V2 Factory from OmnichainGovernanceExecutor to
        //    UniswapWormholeReceiver.
        // - `owner` on the V3 Factory from OmnichainGovernanceExecutor to
        //    UniswapWormholeReceiver.
        // - `owner` on the V4 Pool Manager from OmnichainGovernanceExecutor to
        //    UniswapWormholeReceiver.
        //
        LayerZeroEncoder.encode({
          omnichainProposalSender: Constants.Ethereum.OMNICHAIN_PROPOSAL_SENDER,
          layerZeroChainId: Constants.LayerZero.AVAX_CHAIN_ID,
          remoteCalls: LibCall.newCalls(
            [
              Call({
                target: uniswap.avalanche.v2Factory,
                value: 0,
                data: abi.encodeCall(
                  IUniswapV2Factory.setFeeToSetter, (Constants.Avalanche.WORMHOLE_RECEIVER)
                )
              }),
              Call({
                target: uniswap.avalanche.v3Factory,
                value: 0,
                data: abi.encodeCall(
                  IUniswapV3Factory.setOwner, (Constants.Avalanche.WORMHOLE_RECEIVER)
                )
              }),
              Call({
                target: uniswap.avalanche.poolManager,
                value: 0,
                data: abi.encodeCall(
                  IPoolManager.transferOwnership, (Constants.Avalanche.WORMHOLE_RECEIVER)
                )
              })
            ]
          )
        }),
        // -----------------------------------------------------------------------------------------
        // Action 03:
        //
        // Transfer V2 Fee Setter on Soneium from OptimismPortal2 to CrossChainAccount
        //
        // Context:
        //
        // In prior proposals which initialized fee infrastructure, the system also deployed the
        // latest abstraction used by Soneium, that is the CrossChainAccount. The rest of the
        // protocol on Soneium is still owned by the former, lower level abstraction, the Optimism
        // Portal (technically OptimismPortal2). This action finalizes that transfer on the V2
        // Factory.
        //
        // We set:
        //
        // - `feeToSetter` on the V2 factory to the newly deployed CrossChainAccount
        //
        OptimismPortal2Encoder.encode({
          portal: Constants.Soneium.OPTIMISM_PORTAL2,
          remoteCall: Call({
            target: uniswap.soneium.v2Factory,
            value: 0,
            data: abi.encodeCall(
              IUniswapV2Factory.setFeeToSetter, (Constants.Soneium.CROSS_CHAIN_ACCOUNT)
            )
          })
        }),
        // -----------------------------------------------------------------------------------------
        // Action 04:
        //
        // Transfer V4 Ownership on Soneium from OptimismPortal2 to CrossChainAccount
        //
        // Context:
        //
        // In prior proposals which initialized fee infrastructure, the system also deployed the
        // latest abstraction used by Soneium, that is the CrossChainAccount. The rest of the
        // protocol on Soneium is still owned by the former, lower level abstraction, the Optimism
        // Portal (technically OptimismPortal2). This action finalizes that transfer on the V4
        // Pool Manager.
        //
        // We set:
        //
        // - `owner` on the Pool Manager to the newly deployed CrossChainAccount
        //
        OptimismPortal2Encoder.encode({
          portal: Constants.Soneium.OPTIMISM_PORTAL2,
          remoteCall: Call({
            target: uniswap.soneium.poolManager,
            value: 0,
            data: abi.encodeCall(
              IPoolManager.transferOwnership, (Constants.Soneium.CROSS_CHAIN_ACCOUNT)
            )
          })
        }),
        // -----------------------------------------------------------------------------------------
        // Action 05:
        //
        // Transfer V2 Fee Setter on XLayer from OptimismPortal2 to CrossChainAccount
        //
        // Context:
        //
        // In prior proposals which initialized fee infrastructure, the system also deployed the
        // latest abstraction used by XLayer, that is the CrossChainAccount. The rest of the
        // protocol on XLayer is still owned by the former, lower level abstraction, the Optimism
        // Portal (technically OptimismPortal2). This action finalizes that transfer on the V2
        // Factory.
        //
        // We set:
        //
        // - `feeToSetter` on the V2 factory to the newly deployed CrossChainAccount
        //
        OptimismPortal2Encoder.encode({
          portal: Constants.XLayer.OPTIMISM_PORTAL2,
          remoteCall: Call({
            target: uniswap.xLayer.v2Factory,
            value: 0,
            data: abi.encodeCall(
              IUniswapV2Factory.setFeeToSetter, (Constants.XLayer.CROSS_CHAIN_ACCOUNT)
            )
          })
        }),
        // -----------------------------------------------------------------------------------------
        // Action 06:
        //
        // Transfer V4 Ownership on XLayer from OptimismPortal2 to CrossChainAccount
        //
        // Context:
        //
        // In prior proposals which initialized fee infrastructure, the system also deployed the
        // latest abstraction used by XLayer, that is the CrossChainAccount. The rest of the
        // protocol on XLayer is still owned by the former, lower level abstraction, the Optimism
        // Portal (technically OptimismPortal2). This action finalizes that transfer on the V4
        // Pool Manager.
        //
        // We set:
        //
        // - `owner` on the Pool Manager to the newly deployed CrossChainAccount
        //
        OptimismPortal2Encoder.encode({
          portal: Constants.XLayer.OPTIMISM_PORTAL2,
          remoteCall: Call({
            target: uniswap.xLayer.poolManager,
            value: 0,
            data: abi.encodeCall(
              IPoolManager.transferOwnership, (Constants.XLayer.CROSS_CHAIN_ACCOUNT)
            )
          })
        })
      ]
    )
  });
}

contract MaintenanceProposal is Script {
  Uniswap internal uniswap;

  function run() public {
    uniswap.loadLatest();

    Proposal memory maintenanceProposal = buildMaintenanceProposal(uniswap);
    string memory json = GovernanceSeatbelt.toJson({
      proposal: maintenanceProposal, governorBravo: uniswap.ethereum.governorBravo
    });

    vm.createDir({path: "out/.seatbelt/", recursive: true});
    vm.writeFile("out/.seatbelt/MaintenanceProposal.json", json);
  }
}
