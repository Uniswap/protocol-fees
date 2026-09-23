// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {GovernanceSeatbelt} from "govkit/forge/GovernanceSeatbelt.sol";
import {Call, LibCall} from "govkit/types/Call.sol";
import {Proposal} from "govkit/types/Proposal.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {WormholeChainId} from "govkit/constants/WormholeChainId.sol";
import {WormholeEncoder} from "govkit/bridges/WormholeEncoder.sol";

import {IWormholeSender} from "govkit/interfaces/bridges/IWormholeSender.sol";
import {IUniswapV2Factory} from "govkit/interfaces/IUniswapV2Factory.sol";
import {IUniswapV3Factory} from "govkit/interfaces/IUniswapV3Factory.sol";
import {IPoolManager} from "govkit/interfaces/IPoolManager.sol";

import {INttManagerPeers, IWormhole, IWormholeTransceiver} from "./Interfaces.sol";
import {checkArcPreflight} from "./ArcPreflight.sol";
import "./params/Constants.sol" as Constants;
import {DESCRIPTION} from "./Description.sol";

// -------------------------------------------------------------------------------------------------
// NOTICE:
//
// The proposal has two halves. The Ethereum half registers Arc as a peer on the NTT manager
// and transceiver deployed by proposal 4; both are owned by the Timelock, so only governance can
// do it, and without it UNI burned on Arc never releases on Ethereum. The Arc half
// travels over Wormhole and turns on v2, v3, and v4 fees.
//
// Each half has preconditions on its own chain, so this script has a preflight per chain.
//
// 1. The prerequisite deployment runs the Arc preflight before broadcasting. Repeat
//    `preflightArc()` against Arc before the vote to catch any change to the receiver's
//    authority or sender configuration:
//
//    forge script script/proposal-7/ArcFees.s.sol --sig "preflightArc()" --rpc-url arc
// 2. `run()` against Ethereum runs `preflightEthereum()`, then writes the proposal for Seatbelt.
//    The prerequisite script must have run on Arc first, since `buildProposal` reads its
//    deployments out of the record:
//
//    forge script script/proposal-7/ArcFees.s.sol --rpc-url mainnet
//
// `buildProposal` is a free function so a fork test, and callers outside this repo, build the same
// calls the script writes without deploying the script.
//
// ---
//
// Wormhole does not deliver the Arc message. After the proposal executes, someone must fetch
// the VAA for action 02 from Wormhole's API and call `receiveMessage` on the Arc receiver;
// proposal 4 did this with a finalizer script carrying the VAA bytes. A third-party relayer may
// deliver it first, in which case a later attempt reverts as a replay even though the message ran.
//
/// @dev The proposal's calls. Reads the Ethereum NTT contracts from govkit, the Arc
/// deployments from the record, and the Wormhole message fee from the core bridge, so it needs an
/// Ethereum fork and an initialized recorder.
function buildProposal(Uniswap storage uniswap, Recorder storage recorder)
  view
  returns (Proposal memory)
{
  Constants.smokeCheck();

  // Both Wormhole publications below must carry exactly the core bridge's fee. It is zero today
  // and read here rather than assumed; if it changes between proposal and execution, execution
  // fails and the proposal has to be re-made, which no script can prevent.
  uint256 messageFee = IWormhole(uniswap.ethereum.bridge.wormholeCore).messageFee();

  uint256 chainId = Constants.Arc.CHAIN_ID;

  address arcNttManager =
    recorder.read({chainId: chainId, deploymentName: Constants.Records.NTT_MANAGER});
  address arcTransceiver =
    recorder.read({chainId: chainId, deploymentName: Constants.Records.WORMHOLE_TRANSCEIVER});
  address tokenJar = recorder.read({chainId: chainId, deploymentName: Constants.Records.TOKEN_JAR});
  address v3OpenFeeAdapter =
    recorder.read({chainId: chainId, deploymentName: Constants.Records.V3_OPEN_FEE_ADAPTER});
  address v4FeeAdapter =
    recorder.read({chainId: chainId, deploymentName: Constants.Records.V4_FEE_ADAPTER});

  // ---------------------------------------------------------------------------------------------
  // Action 00
  //
  // Set the Arc `WormholeTransceiver` proxy as a peer on the Ethereum
  // `WormholeTransceiver` proxy.
  //
  // `setWormholePeer` is payable because it publishes a Wormhole message announcing the
  // registration.
  //
  // Parameters:
  //
  // - `target`: Ethereum WormholeTransceiver proxy, owned by the Timelock.
  // - `value`: Wormhole core message fee, read above.
  // - `peerChainId`: Wormhole-defined Arc Chain Id.
  // - `peerContract`: Arc WormholeTransceiver proxy.
  //
  Call memory setEthereumTransceiverPeer = Call({
    target: uniswap.ethereum.wormholeTransceiver,
    value: messageFee,
    data: abi.encodeCall(
      IWormholeTransceiver.setWormholePeer,
      (Constants.Arc.WORMHOLE_CHAIN_ID, WormholeEncoder.toWormholeFormat(arcTransceiver))
    )
  });

  // ---------------------------------------------------------------------------------------------
  // Action 01
  //
  // Set the Arc `NttManager` proxy as a peer on the Ethereum `NttManager` proxy.
  //
  // Parameters:
  //
  // - `target`: Ethereum NttManager proxy, owned by the Timelock.
  // - `peerChainId`: Wormhole-defined Arc Chain Id.
  // - `peerContract`: Arc NttManager proxy.
  // - `decimals`: UNI decimals on Arc.
  // - `inboundLimit`: Set to zero when rate limiter is disabled, matching BNB Chain and Polygon.
  //
  Call memory setEthereumNttManagerPeer = Call({
    target: uniswap.ethereum.nttManager,
    value: 0,
    data: abi.encodeCall(
      INttManagerPeers.setPeer,
      (Constants.Arc.WORMHOLE_CHAIN_ID, WormholeEncoder.toWormholeFormat(arcNttManager), 18, 0)
    )
  });

  // ---------------------------------------------------------------------------------------------
  // Action 02
  //
  // Turn on v2, v3, and v4 fees on Arc, as one Wormhole message carrying the three remote
  // calls below.
  //
  // All three run from the `UniswapWormholeMessageReceiver` on Arc. Each depends on the
  // receiver already holding the authority named in its block; that handoff from the deploying
  // team is a prerequisite for this proposal, not part of it, and `preflight()` asserts it.

  // Remote call 00
  //
  // Set `UniswapV2Factory.feeTo` to `TokenJar`. Requires the receiver to be the factory's
  // `feeToSetter`.
  //
  // Parameters:
  //
  // - `target`: Arc Uniswap V2 Factory.
  // - `_feeTo`: Arc TokenJar.
  //
  Call memory setV2FeeTo = Call({
    target: Constants.Arc.V2_FACTORY,
    value: 0,
    data: abi.encodeCall(IUniswapV2Factory.setFeeTo, (tokenJar))
  });

  // Remote call 01
  //
  // Set `UniswapV3Factory.owner` to `V3OpenFeeAdapter`, which collects fees as factory owner.
  // Requires the receiver to be the factory's `owner`.
  //
  // Parameters:
  //
  // - `target`: Arc Uniswap V3 Factory.
  // - `_owner`: Arc V3OpenFeeAdapter.
  //
  Call memory setV3Owner = Call({
    target: Constants.Arc.V3_FACTORY,
    value: 0,
    data: abi.encodeCall(IUniswapV3Factory.setOwner, (v3OpenFeeAdapter))
  });

  // Remote call 02
  //
  // Set `PoolManager.protocolFeeController` to `V4FeeAdapter`. Requires the receiver to be the
  // PoolManager's `owner`.
  //
  // Parameters:
  //
  // - `target`: Arc Uniswap V4 Pool Manager.
  // - `controller`: Arc V4FeeAdapter.
  //
  Call memory setV4FeeController = Call({
    target: Constants.Arc.POOL_MANAGER,
    value: 0,
    data: abi.encodeCall(IPoolManager.setProtocolFeeController, (v4FeeAdapter))
  });

  // The `sendMessage` envelope, see `encodeWormhole`:
  //
  // - `value`: Wormhole core message fee, read above.
  // - `targets`, `values`, `calldatas`: Remote calls 00, 01, and 02, split into parallel arrays.
  // - `messageReceiver`: Arc `UniswapWormholeMessageReceiver`, which executes them.
  // - `receiverChainId`: Wormhole-defined Arc Chain Id.
  //
  Call[] memory arcCalls = LibCall.newCalls([setV2FeeTo, setV3Owner, setV4FeeController]);

  Call memory activateArcFees = encodeWormhole(arcCalls, messageFee);

  // ---------------------------------------------------------------------------------------------
  // Output
  //
  // The inputs to `GovernorBravo.propose(targets, values, signatures, datas, description)`,
  // bundling the three actions above. `run()` writes them to disk for Seatbelt; nothing here
  // broadcasts, and the `propose` call itself is made separately.
  //
  // Parameters:
  //
  // - `targets`, `values`, `signatures`, `datas`: Actions 00, 01, and 02, split into parallel
  //   arrays by `Proposal.toGovernorBravoInputs()`.
  // - `description`: `DESCRIPTION`, which is still placeholder text.
  //
  return Proposal({
    description: DESCRIPTION,
    calls: LibCall.newCalls(
      [setEthereumTransceiverPeer, setEthereumNttManagerPeer, activateArcFees]
    )
  });
}

/// @dev Encodes a batch of Arc calls as a single Wormhole message from the Timelock.
/// @dev This is `WormholeEncoder.encode` with the chain id supplied directly. The encoder maps
/// an EIP-155 chain id to a Wormhole one through `WormholeChainId`, which does not know Arc
/// yet; that mapping lands in govkit once this proposal has executed, at which point this function
/// collapses back to a `WormholeEncoder.encode` call.
function encodeWormhole(Call[] memory remoteCalls, uint256 value) pure returns (Call memory) {
  address[] memory targets = new address[](remoteCalls.length);
  uint256[] memory values = new uint256[](remoteCalls.length);
  bytes[] memory datas = new bytes[](remoteCalls.length);

  for (uint256 i; i < remoteCalls.length; i++) {
    targets[i] = remoteCalls[i].target;
    values[i] = remoteCalls[i].value;
    datas[i] = remoteCalls[i].data;
  }

  return Call({
    target: Constants.Ethereum.WORMHOLE_SENDER,
    value: value,
    data: abi.encodeCall(
      IWormholeSender.sendMessage,
      (targets, values, datas, Constants.Arc.WORMHOLE_RECEIVER, Constants.Arc.WORMHOLE_CHAIN_ID)
    )
  });
}

contract ArcFees is Script {
  Recorder internal recorder;
  Uniswap internal uniswap;

  constructor() {
    uniswap.loadLatest();
  }

  /// @dev Asserts the Ethereum-side state, then writes the proposal for Governance Seatbelt.
  function run() external {
    preflightEthereum();

    recorder.initialize({scriptName: Constants.RECORD_NAME});

    string memory path = "./out/.seatbelt/ArcFeeProposal.json";
    vm.createDir("./out/.seatbelt/", true);
    vm.writeFile({
      path: path,
      data: GovernanceSeatbelt.toJson({
        proposal: buildProposal(uniswap, recorder), governorBravo: uniswap.ethereum.governorBravo
      })
    });
    console.log("wrote", path);
  }

  /// @dev `preflightArc()` at a block the caller names. Pin the fork to the same block so the
  /// two cannot disagree:
  /// `--sig "preflightArc(uint256)" $B --rpc-url arc --fork-block-number $B`.
  function preflightArc(uint256 blockNumber) public view {
    require(block.number == blockNumber, "block number");
    preflightArc();
  }

  /// @dev Asserts Arc is in the state action 02 assumes: the receiver trusts the Ethereum
  /// sender, accepts messages addressed to Arc's Wormhole chain id, and holds the authority each
  /// remote call needs. Run against Arc. Logs the block it ran at.
  function preflightArc() public view {
    checkArcPreflight();
    console.log("preflightArc at block", block.number);
  }

  /// @dev `preflightEthereum()` at a block the caller names. Pin the fork to the same block so the
  /// two cannot disagree:
  /// `--sig "preflightEthereum(uint256)" $B --rpc-url mainnet --fork-block-number $B`.
  function preflightEthereum(uint256 blockNumber) public view {
    require(block.number == blockNumber, "block number");
    preflightEthereum();
  }

  /// @dev Asserts Ethereum is in the state actions 00 through 02 assume: every target answers to
  /// the Timelock, and neither NTT contract knows Arc yet. `setWormholePeer` reverts on an
  /// existing peer and `setPeer` silently overwrites one, so both are checked up front. Run
  /// against Ethereum. Logs the block it ran at.
  function preflightEthereum() public view {
    Constants.smokeCheck();

    require(block.chainid == ChainId.Ethereum, "not Ethereum");
    console.log("preflightEthereum at block", block.number);

    address timelock = uniswap.ethereum.timelock;
    uint16 arcWormholeChainId = Constants.Arc.WORMHOLE_CHAIN_ID;

    // WormholeSender. The constant restates govkit's per-destination field for a chain govkit
    // knows; the two must agree.
    require(
      Constants.Ethereum.WORMHOLE_SENDER == uniswap.ethereum.bridge.bnbChain,
      "wormholeSender: constant differs from govkit"
    );
    require(
      IWormholeSender(Constants.Ethereum.WORMHOLE_SENDER).owner() == timelock,
      "wormholeSender.owner"
    );

    // WormholeTransceiver
    IWormholeTransceiver transceiver = IWormholeTransceiver(uniswap.ethereum.wormholeTransceiver);

    require(transceiver.owner() == timelock, "wormholeTransceiver.owner");
    require(
      transceiver.getWormholePeer(arcWormholeChainId) == bytes32(0), "wormholeTransceiver.peer set"
    );

    // NttManager
    INttManagerPeers nttManager = INttManagerPeers(uniswap.ethereum.nttManager);

    require(nttManager.owner() == timelock, "nttManager.owner");
    require(nttManager.getPeer(arcWormholeChainId).peerAddress == bytes32(0), "nttManager.peer set");
  }
}
