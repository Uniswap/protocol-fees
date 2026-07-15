// SPDX-License-Identifier: AGPl-3.0-only
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {InboxEncoder} from "govkit/bridges/InboxEncoder.sol";
import {GovernanceSeatbelt} from "lib/govkit/src/forge/GovernanceSeatbelt.sol";
import {Call, LibCall} from "lib/govkit/src/types/Call.sol";
import {Proposal} from "lib/govkit/src/types/Proposal.sol";

import {IUniswapV2Factory} from "govkit/interfaces/IUniswapV2Factory.sol";
import {IUniswapV3Factory} from "govkit/interfaces/IUniswapV3Factory.sol";
import {IPoolManager} from "govkit/interfaces/IPoolManager.sol";
import {ITokenJar} from "govkit/interfaces/ITokenJar.sol";
import {IReleaser} from "govkit/interfaces/IReleaser.sol";
import {IV3OpenFeeAdapter} from "govkit/interfaces/IV3OpenFeeAdapter.sol";

import "./Constants.sol" as Constants;

string constant DESCRIPTION = "TODO";

contract RobinhoodFees is Script {
  Recorder internal recorder;
  Uniswap internal uniswap;

  function run() external {
    uniswap.loadLatest();
    recorder.initialize({scriptName: "DeployFeeInfraRobinhood"});

    address tokenJar =
      recorder.read({chainId: Constants.Robinhood.CHAIN_ID, deploymentName: "TokenJar"});
    address v3OpenFeeAdapter =
      recorder.read({chainId: Constants.Robinhood.CHAIN_ID, deploymentName: "V3OpenFeeAdapter"});

    // ---------------------------------------------------------------------------------------------
    // 00: Set Fee Receiver on V2 Factor to  on Robinhood
    //
    Call memory v2SetFeeTo = InboxEncoder.encode({
      inbox: Constants.Ethereum.RH_INBOX,
      timelock: uniswap.ethereum.timelock,
      remoteCall: Call({
        target: Constants.Robinhood.V2_FACTORY,
        value: 0,
        data: abi.encodeCall(IUniswapV2Factory.setFeeTo, (tokenJar))
      })
    });

    // ---------------------------------------------------------------------------------------------
    // 01: Transfer Ownership of V3 Factory to V3 Open Fee Adapter on Robinhood
    //
    Call memory v3SetOwner = InboxEncoder.encode({
      inbox: Constants.Ethereum.RH_INBOX,
      timelock: uniswap.ethereum.timelock,
      remoteCall: Call({
        target: Constants.Robinhood.V3_FACTORY,
        value: 0,
        data: abi.encodeCall(IUniswapV3Factory.setOwner, (v3OpenFeeAdapter))
      })
    });

    Proposal memory robinhoodFeeProposal =
      Proposal({description: DESCRIPTION, calls: LibCall.newCalls([v2SetFeeTo, v3SetOwner])});

    vm.createDir("./out/.seatbelt/", true);
    vm.writeFile({
      path: "./out/.seatbelt/RobinhoodFeeProposal.json",
      data: GovernanceSeatbelt.toJson({
        proposal: robinhoodFeeProposal, governorBravo: uniswap.ethereum.governorBravo
      })
    });
  }
}
