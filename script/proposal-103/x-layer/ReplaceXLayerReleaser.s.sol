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

import {IDecayingThresholdSetter} from "../../../src/interfaces/IDecayingThresholdSetter.sol";
import {RECORD_NAME, Records, smokeCheck} from "./Constants.sol";
import {checkNewReleaser, checkThresholdSetter} from "./ReleaserCheck.sol";

// -------------------------------------------------------------------------------------------------
// NOTICE:
//
// This action is two Ethereum calls, each of which sends one message to X Layer. Uniswap's
// CrossChainAccount on X Layer owns the TokenJar and is the {DecayingThresholdSetter}'s governance.
// It makes one call per message, and only for messages the Timelock sends through X Layer's
// L1CrossDomainMessenger:
//
// - Message 00, {buildReplaceReleaserCall}: set the TokenJar's releaser to the new releaser.
// - Message 01, {buildStartDecayCall}: start the {DecayingThresholdSetter}. It follows message 00
//   because {DecayingThresholdSetter-start} requires the TokenJar to release through the new
//   releaser.
//
// X Layer relays the messages in the order the proposal sends them. If message 01 fails on X Layer,
// the L2CrossDomainMessenger records it as failed, and anyone can replay it. Until then the new
// releaser charges `XLayer.START_THRESHOLD`.
//
// `prereq/DeployXLayerReleaser.s.sol` deploys the new releaser and the {DecayingThresholdSetter}
// before the vote, and records their addresses in `.records/XLayer.json`. This script reads them
// from there.
//
// `../Proposal103.s.sol` runs `preflightEthereum()`. Before proposing, run `preflightXLayer()`
// against X Layer. It checks the settings of the new releaser and the setter, and that the
// Timelock still controls the CrossChainAccount:
//
//    forge script script/proposal-103/x-layer/ReplaceXLayerReleaser.s.sol \
//      --sig "preflightXLayer()" --rpc-url xlayer
//
// The OP Stack bridge relays the messages to X Layer by itself once the proposal executes.
//

/// @dev Returns the call that sends message 00, which replaces the X Layer releaser. A free
///      function, so the fork tests and anything outside this repo build the call in the proposal
///      without deploying a script. Reads the new releaser from `recorder`. Assumes
///      `recorder` is initialized.
function buildReplaceReleaserCall(Uniswap storage uniswap, Recorder storage recorder)
  view
  returns (Call memory)
{
  smokeCheck();
  address newReleaser = readNewReleaser(recorder);

  // Set the X Layer TokenJar's releaser to the new releaser, as one message through X Layer's
  // L1CrossDomainMessenger to the CrossChainAccount, which owns the TokenJar.

  // Message 00, remote call 00
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

/// @dev Returns the call that sends message 01, which starts the {DecayingThresholdSetter}'s decay.
///      A free function for the same reason as {buildReplaceReleaserCall}. Reads the setter from
///      `recorder`. Assumes `recorder` is initialized.
function buildStartDecayCall(Uniswap storage uniswap, Recorder storage recorder)
  view
  returns (Call memory)
{
  smokeCheck();
  address thresholdSetter = readThresholdSetter(recorder);

  // Message 01, remote call 00
  //
  // Start the decay. {DecayingThresholdSetter-start} makes the setter the releaser's
  // threshold-setter and sets the threshold to `START_THRESHOLD`. It requires:
  //
  // - the CrossChainAccount to be the setter's `GOVERNANCE`;
  // - the setter to own the releaser;
  // - the TokenJar to release through the releaser, which message 00 sets;
  // - the releaser's threshold to be at least `START_THRESHOLD`.
  //
  // Parameters:
  //
  // - `target`: the {DecayingThresholdSetter}.
  //
  Call memory start = Call({
    target: thresholdSetter, value: 0, data: abi.encodeCall(IDecayingThresholdSetter.start, ())
  });

  // The `sendMessage` envelope, as for message 00, with the encoder's default `_minGasLimit`,
  // 200,000.
  return L1CrossDomainMessengerEncoder.encode({
    l1CrossDomainMessenger: uniswap.ethereum.bridge.xLayer,
    crossChainAccount: uniswap.xLayer.crossChainAccount,
    remoteCall: start
  });
}

/// @dev Returns the new releaser's address from `recorder`. Assumes `recorder` is initialized.
function readNewReleaser(Recorder storage recorder) view returns (address) {
  return recorder.read({chainId: ChainId.XLayer, deploymentName: Records.RELEASER});
}

/// @dev Returns the {DecayingThresholdSetter}'s address from `recorder`. Assumes `recorder` is
///      initialized.
function readThresholdSetter(Recorder storage recorder) view returns (address) {
  return recorder.read({chainId: ChainId.XLayer, deploymentName: Records.THRESHOLD_SETTER});
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
  ///      still has the old releaser, and the recorded new releaser and {DecayingThresholdSetter}
  ///      pass {checkNewReleaser} and {checkThresholdSetter}. Run against X Layer. Logs the block
  ///      it ran at.
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

    // New releaser and {DecayingThresholdSetter}
    address newReleaser = readNewReleaser(recorder);
    address thresholdSetter = readThresholdSetter(recorder);
    checkNewReleaser(uniswap, newReleaser, thresholdSetter);
    checkThresholdSetter(uniswap, thresholdSetter, newReleaser);
    console.log("new releaser ready", newReleaser);
    console.log("threshold setter ready", thresholdSetter);
  }

  /// @dev Asserts the TokenJar releases through the new releaser and the
  /// {DecayingThresholdSetter}'s decay has started. The fork tests call it after they relay the
  /// proposal's messages. After
  ///      the messages execute on X Layer, run it there:
  ///      `--sig "postflightXLayer()" --rpc-url xlayer`.
  function postflightXLayer() public {
    require(block.chainid == ChainId.XLayer, "not X Layer");
    console.log("postflightXLayer ReplaceXLayerReleaser at block", block.number);
    _initializeRecorder();

    address newReleaser = readNewReleaser(recorder);
    require(ITokenJar(uniswap.xLayer.tokenJar).releaser() == newReleaser, "tokenJar.releaser");
    console.log("releaser replaced", newReleaser);

    // Assert the recorded setter belongs to the new releaser, so its `startTime` describes the
    // releaser the TokenJar now uses.
    IDecayingThresholdSetter setter = IDecayingThresholdSetter(readThresholdSetter(recorder));
    require(address(setter.RELEASER()) == newReleaser, "thresholdSetter.RELEASER");

    // Assert message 01 started the decay. A message 01 that failed on X Layer, for example by
    // arriving before message 00, leaves `startTime` at 0.
    require(setter.startTime() != 0, "thresholdSetter.startTime");
    console.log("decay started", address(setter));
  }

  /// @dev Points `recorder` at the record the prerequisite script wrote.
  function _initializeRecorder() internal {
    recorder.initialize({scriptName: _recordName()});
  }

  /// @dev Returns the record file that holds the new releaser and the {DecayingThresholdSetter}.
  ///      Tests override it to read a deployment they made on the fork.
  function _recordName() internal view virtual returns (string memory) {
    return RECORD_NAME;
  }
}
