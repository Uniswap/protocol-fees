// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import "./Constants.sol" as Constants;
import {
  IOptimismPortal,
  IUniswapV2Factory,
  IUniswapV3Factory,
  IBridgehub,
  IGovernorBravo
} from "./Interfaces.sol";
import {L2TransactionRequestDirect} from "./ZkSync.sol";
import {ProposalAction, toItems} from "./Types.sol";
using {toItems} for ProposalAction[];

import {PolygonSender} from "./PolygonSender.sol";

string constant PROPOSAL_DESCRIPTION = "TODO";

/// @title Activate L2's (Plus Celo Retry)
contract ActivateL2Proposals is Script {
  /// @notice Runs the actions
  function run() public {
    // check addresses are non-zero.
    Constants.vibeCheck();

    // construct actions & decompose to governor parameters.
    (
      address[] memory targets,
      uint256[] memory values,
      string[] memory signatures,
      bytes[] memory datas
    ) = _getActions().toItems();

    // initiate the broadcast.
    vm.startBroadcast();

    // propose.
    IGovernorBravo(Constants.L1.GOVERNOR)
      .propose(targets, values, signatures, datas, PROPOSAL_DESCRIPTION);

    // stop the broadcast.
    vm.stopBroadcast();
  }

  function _getActions() internal pure returns (ProposalAction[] memory actions) {
    actions = new ProposalAction[](10);

    // ---------------------------------------------------------------------------------------------
    // STEP 1:
    //
    // Retry Celo V2
    //
    // uses optimism cannon bridge
    actions[0] = ProposalAction({
      target: Constants.L1.CELO_PORTAL,
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IOptimismPortal.depositTransaction,
        (
          Constants.Celo.V2_FACTORY,
          0,
          0,
          false,
          abi.encodeCall(IUniswapV2Factory.setFeeTo, (Constants.Celo.TOKEN_JAR))
        )
      )
    });

    // ---------------------------------------------------------------------------------------------
    // STEP 2:
    //
    // Retry Celo V3
    //
    // uses optimism cannon bridge
    actions[1] = ProposalAction({
      target: Constants.L1.CELO_PORTAL,
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IOptimismPortal.depositTransaction,
        (
          Constants.Celo.V3_FACTORY,
          0,
          0,
          false,
          abi.encodeCall(IUniswapV3Factory.setOwner, (Constants.Celo.TOKEN_JAR))
        )
      )
    });

    // ---------------------------------------------------------------------------------------------
    // STEP 3:
    //
    // BSC V2 (TODO)
    // actions[2] = ProposalAction();

    // ---------------------------------------------------------------------------------------------
    // STEP 4:
    //
    // BSC V3 (TODO)
    // actions[3] = ProposalAction();

    // ---------------------------------------------------------------------------------------------
    // STEP 5:
    //
    // Polygon V2
    //
    // uses PolygonSender contract (custom)
    actions[4] = ProposalAction({
      target: Constants.L1.POLYGON_SENDER,
      value: 0,
      signature: "",
      data: abi.encodeCall(
        PolygonSender.sendIt,
        (
          Constants.Polygon.V2_FACTORY,
          abi.encodeCall(IUniswapV2Factory.setFeeTo, (Constants.Polygon.TOKEN_JAR))
        )
      )
    });

    // ---------------------------------------------------------------------------------------------
    // STEP 6:
    //
    // Polyon V3
    //
    // uses PolygonSender contract (custom)
    actions[5] = ProposalAction({
      target: Constants.L1.POLYGON_SENDER,
      value: 0,
      signature: "",
      data: abi.encodeCall(
        PolygonSender.sendIt,
        (
          Constants.Polygon.V3_FACTORY,
          abi.encodeCall(IUniswapV3Factory.setOwner, (Constants.Polygon.TOKEN_JAR))
        )
      )
    });

    // ---------------------------------------------------------------------------------------------
    // STEP 7:
    //
    // Avalanche V2 (TODO)
    // actions[6] = ProposalAction();

    // ---------------------------------------------------------------------------------------------
    // STEP 8:
    //
    // Avalanche V3 (TODO)
    // actions[7] = ProposalAction();

    // ---------------------------------------------------------------------------------------------
    // STEP 9:
    //
    // zkSync V2
    actions[8] = ProposalAction({
      target: Constants.L1.ZK_SYNC_HUB,
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IBridgehub.requestL2TransactionDirect,
        (L2TransactionRequestDirect({
            chainId: Constants.ZkSync.ZK_SYNC_ERA_ID,
            mintValue: 0x00, // TODO: THIS SHOULD BE DYNAMICALLY CHOSEN
            // (bridgeHub.l2TransactionBaseCost)
            l2Contract: Constants.ZkSync.V2_FACTORY,
            l2Value: 0,
            l2Calldata: abi.encodeCall(IUniswapV2Factory.setFeeTo, (Constants.ZkSync.TOKEN_JAR)),
            l2GasLimit: 0x00, // TODO: CHECK THIS
            l2GasPerPubdataByteLimit: 0x00, // TODO: CHECK THIS
            factoryDeps: new bytes[](0),
            refundRecipient: Constants.L1.GOVERNOR // TODO: CHECK THIS
          }))
      )
    });

    // ---------------------------------------------------------------------------------------------
    // STEP 10:
    //
    // zkSync V3
    actions[9] = ProposalAction({
      target: Constants.L1.ZK_SYNC_HUB,
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IBridgehub.requestL2TransactionDirect,
        (L2TransactionRequestDirect({
            chainId: Constants.ZkSync.ZK_SYNC_ERA_ID,
            mintValue: 0x00, // TODO: THIS SHOULD BE DYNAMICALLY CHOSEN
            // (bridgeHub.l2TransactionBaseCost)
            l2Contract: Constants.ZkSync.V3_FACTORY,
            l2Value: 0,
            l2Calldata: abi.encodeCall(IUniswapV3Factory.setOwner, (Constants.Polygon.TOKEN_JAR)),
            l2GasLimit: 0x00, // TODO: CHECK THIS
            l2GasPerPubdataByteLimit: 0x00, // TODO: CHECK THIS
            factoryDeps: new bytes[](0),
            refundRecipient: Constants.L1.GOVERNOR // TODO: CHECK THIS
          }))
      )
    });
  }
}
