// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {Call} from "govkit/types/Call.sol";
import {L1CrossDomainMessengerEncoder} from "govkit/bridges/L1CrossDomainMessengerEncoder.sol";
import {ITokenJar} from "govkit/interfaces/ITokenJar.sol";
import {ICrossChainAccount} from "govkit/interfaces/bridges/ICrossChainAccount.sol";
import {Predeploys} from "@eth-optimism-bedrock/src/libraries/Predeploys.sol";
import {
  ICrossDomainMessenger
} from "@eth-optimism-bedrock/interfaces/universal/ICrossDomainMessenger.sol";

import {RECORD_NAME, Records, smokeCheck} from "./Constants.sol";
import {checkNewReleaser} from "./ReleaserCheck.sol";

// -------------------------------------------------------------------------------------------------
// NOTICE:
//
// This action is one Ethereum call that sends one message to X Layer. The X Layer TokenJar is owned
// by Uniswap's CrossChainAccount there, which only forwards calls relayed from the Timelock via
// L2CrossDomainMessenger. The Timelock sends through X Layer's L1CrossDomainMessenger, the
// message is delivered to the CrossChainAccount, which calls the TokenJar.
//
// The new releaser is deployed ahead of the vote by `prereq/DeployAggLayerReleaser.s.sol`, which
// records its address in `.records/XLayer.json`. This script reads it from there.
//
// `../Proposal103.s.sol` runs `preflightEthereum()`. Run `preflightXLayer()` against X Layer before
// proposing, to check that the new releaser is deployed and authority is transferred, and that the
// Timelock still controls the CrossChainAccount:
//
//    forge script script/proposal-103/x-layer/ReplaceXLayerReleaser.s.sol \
//      --sig "preflightXLayer()" --rpc-url xlayer
//
// The OP Stack bridge relays the message to X Layer by itself once the proposal executes.
//

/// @dev Returns the call that replaces the X Layer releaser. A free function so the fork tests, and
///      anything outside this repo, build the same call the proposal carries without deploying a
///      script. Reads the new releaser from `recorder`, which must be initialized.
function buildReplaceReleaserCall(Uniswap storage uniswap, Recorder storage recorder)
  view
  returns (Call memory)
{
  smokeCheck();
  address newReleaser = readNewReleaser(recorder);

  // Set the X Layer TokenJar's releaser to the new releaser, as one message through X Layer's
  // L1CrossDomainMessenger to the CrossChainAccount, which owns the TokenJar.

  // Remote call 00
  //
  // Set `TokenJar.releaser` to the new releaser. Requires the CrossChainAccount to be the
  // TokenJar's `owner`.
  //
  // Parameters:
  //
  // - `target`: X Layer TokenJar.
  // - `_releaser`: the new releaser.
  //
  Call memory setReleaser = Call({
    target: uniswap.xLayer.tokenJar,
    value: 0,
    data: abi.encodeCall(ITokenJar.setReleaser, (newReleaser))
  });

  // The `sendMessage` envelope, see `L1CrossDomainMessengerEncoder.encode`:
  //
  // - `target`: X Layer's L1CrossDomainMessenger on Ethereum.
  // - `_target`: X Layer CrossChainAccount, which runs remote call 00 through `forward`.
  // - `_minGasLimit`: the encoder's default, 200,000.
  //
  return L1CrossDomainMessengerEncoder.encode({
    l1CrossDomainMessenger: uniswap.ethereum.bridge.xLayer,
    crossChainAccount: uniswap.xLayer.crossChainAccount,
    remoteCall: setReleaser
  });
}

/// @dev Returns the new releaser's address from `recorder`, which must be initialized.
function readNewReleaser(Recorder storage recorder) view returns (address) {
  return recorder.read({chainId: ChainId.XLayer, deploymentName: Records.RELEASER});
}

contract ReplaceXLayerReleaser is Script {
  Uniswap internal uniswap;
  Recorder internal recorder;

  constructor() {
    uniswap.loadLatest();
  }

  /// @dev `preflightEthereum()` at a specified block. Pin the fork to the same block so the
  ///      two cannot disagree:
  ///      `--sig "preflightEthereum(uint256)" $B --rpc-url mainnet --fork-block-number $B`.
  function preflightEthereum(uint256 blockNumber) public view {
    require(block.number == blockNumber, "block number");
    preflightEthereum();
  }

  /// @dev Asserts Ethereum is in the state this action assumes: X Layer's L1CrossDomainMessenger
  ///      is live and pointed at X Layer's L2CrossDomainMessenger. Run against Ethereum. Logs the
  ///      block it ran at.
  function preflightEthereum() public view {
    require(block.chainid == ChainId.Ethereum, "not Ethereum");
    console.log("preflightEthereum ReplaceXLayerReleaser at block", block.number);

    ICrossDomainMessenger messenger = ICrossDomainMessenger(uniswap.ethereum.bridge.xLayer);
    require(
      address(messenger.OTHER_MESSENGER()) == Predeploys.L2_CROSS_DOMAIN_MESSENGER,
      "l1CrossDomainMessenger.other"
    );
    require(!messenger.paused(), "l1CrossDomainMessenger.paused");
  }

  /// @dev `preflightXLayer()` at a specified block. Pin the fork to the same block so the
  ///      two cannot disagree:
  ///      `--sig "preflightXLayer(uint256)" $B --rpc-url xlayer --fork-block-number $B`.
  function preflightXLayer(uint256 blockNumber) public {
    require(block.number == blockNumber, "block number");
    preflightXLayer();
  }

  /// @dev Asserts X Layer is in the state this action assumes: the message path from the Timelock
  ///      reaches the CrossChainAccount, the CrossChainAccount owns the TokenJar, the TokenJar
  ///      still has the old releaser, and the recorded new releaser passes `checkNewReleaser`.
  ///      Run against X Layer. Logs the block it ran at.
  function preflightXLayer() public {
    smokeCheck();
    _initializeRecorder();

    require(block.chainid == ChainId.XLayer, "not X Layer");
    console.log("preflightXLayer ReplaceXLayerReleaser at block", block.number);

    address crossChainAccount = uniswap.xLayer.crossChainAccount;
    ITokenJar tokenJar = ITokenJar(uniswap.xLayer.tokenJar);

    // Assert the message path: the L2 messenger accepts X Layer's L1 messenger, and the
    // CrossChainAccount accepts the L2 messenger relaying for the Timelock.
    require(
      address(ICrossDomainMessenger(Predeploys.L2_CROSS_DOMAIN_MESSENGER).OTHER_MESSENGER())
        == uniswap.ethereum.bridge.xLayer,
      "l2CrossDomainMessenger.other"
    );
    require(
      ICrossChainAccount(crossChainAccount).messenger() == Predeploys.L2_CROSS_DOMAIN_MESSENGER,
      "crossChainAccount.messenger"
    );
    require(
      ICrossChainAccount(crossChainAccount).l1Owner() == uniswap.ethereum.timelock,
      "crossChainAccount.l1Owner"
    );

    // TokenJar
    require(tokenJar.owner() == crossChainAccount, "tokenJar.owner");
    require(tokenJar.releaser() == uniswap.xLayer.releaser, "tokenJar.releaser");

    // New releaser
    address newReleaser = readNewReleaser(recorder);
    checkNewReleaser(uniswap, newReleaser);
    console.log("new releaser ready", newReleaser);
  }

  /// @dev Asserts the TokenJar's releaser is the new releaser. The fork tests call this after
  ///      relaying the proposal's message; after the message lands onchain, run it against X
  ///      Layer to verify the outcome: `--sig "postflightXLayer()" --rpc-url xlayer`.
  function postflightXLayer() public {
    require(block.chainid == ChainId.XLayer, "not X Layer");
    console.log("postflightXLayer ReplaceXLayerReleaser at block", block.number);
    _initializeRecorder();

    address newReleaser = readNewReleaser(recorder);
    require(ITokenJar(uniswap.xLayer.tokenJar).releaser() == newReleaser, "tokenJar.releaser");
    console.log("releaser replaced", newReleaser);
  }

  /// @dev Points `recorder` at the record the prerequisite script wrote.
  function _initializeRecorder() internal {
    recorder.initialize({scriptName: _recordName()});
  }

  /// @dev The record file to read the new releaser from. Tests override this with a test record
  ///      name to read a deployment they made on the fork.
  function _recordName() internal view virtual returns (string memory) {
    return RECORD_NAME;
  }
}
