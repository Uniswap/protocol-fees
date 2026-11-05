// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {Proposal} from "govkit/types/Proposal.sol";
import {LibCall} from "govkit/types/Call.sol";
import {GovernanceSeatbelt} from "govkit/forge/GovernanceSeatbelt.sol";

import {DESCRIPTION} from "./Description.sol";
import {RECORD_NAME} from "./x-layer/Constants.sol";
import {
  ReplaceXLayerReleaser,
  buildReplaceReleaserCall
} from "./x-layer/ReplaceXLayerReleaser.s.sol";
import {
  UpgradeVolatileHook,
  buildUpgradeVolatileHookCall
} from "./volatile-hook/UpgradeVolatileHook.s.sol";

// -------------------------------------------------------------------------------------------------
// NOTICE:
//
// The proposal includes two actions, each defined in its own directory with its own parameters,
// preflights and tests. This script aggregates them.
//
// - Action 00, `volatile-hook/`: upgrade the VolatilePairHook on Ethereum, the proposal's headline.
// - Action 01, `x-layer/`: replace the X Layer TokenJar's releaser.
//
// 1. Run the X Layer preflight against X Layer before proposing; see `x-layer/`.
// 2. `run()` against Ethereum runs both actions' Ethereum preflights, then writes the proposal for
//    Seatbelt:
//
//    forge script script/proposal-103/Proposal103.s.sol --rpc-url mainnet
//

/// @dev The proposal's calls. A free function so the fork tests, and anything outside this repo,
///      build the same calls the script writes without deploying the script. Reads the new
///      releaser from `recorder`, which must be initialized.
function buildProposal(Uniswap storage uniswap, Recorder storage recorder)
  view
  returns (Proposal memory)
{
  return Proposal({
    description: DESCRIPTION,
    calls: LibCall.newCalls(
      [buildUpgradeVolatileHookCall(), buildReplaceReleaserCall(uniswap, recorder)]
    )
  });
}

contract Proposal103 is Script {
  Uniswap internal uniswap;
  Recorder internal recorder;

  constructor() {
    uniswap.loadLatest();
  }

  /// @dev Asserts both actions' Ethereum state, then writes the proposal for Governance Seatbelt.
  ///      It does not broadcast a transaction.
  ///      Run against Ethereum: `forge script ... --rpc-url mainnet`.
  function run() external {
    preflightEthereum();
    recorder.initialize({scriptName: _recordName()});

    string memory path = "./out/.seatbelt/Proposal103.json";
    vm.createDir("./out/.seatbelt/", true);
    vm.writeFile({
      path: path,
      data: GovernanceSeatbelt.toJson({
        proposal: buildProposal(uniswap, recorder), governorBravo: uniswap.ethereum.governorBravo
      })
    });
    console.log("wrote", path);
  }

  /// @dev Runs both actions' Ethereum preflights. Run against Ethereum.
  function preflightEthereum() public {
    new ReplaceXLayerReleaser().preflightEthereum();
    new UpgradeVolatileHook().preflightEthereum();
  }

  /// @dev The record file to read the new releaser from.
  function _recordName() internal view virtual returns (string memory) {
    return RECORD_NAME;
  }
}
