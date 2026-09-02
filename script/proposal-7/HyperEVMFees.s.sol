// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";

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

import {
  INttManagerPeers,
  IUniswapWormholeMessageReceiver,
  IWormhole,
  IWormholeTransceiver
} from "./Interfaces.sol";
import "./params/Constants.sol" as Constants;
import {DESCRIPTION} from "./Description.sol";

// -------------------------------------------------------------------------------------------------
// NOTICE:
//
// The proposal has two halves. The Ethereum half registers HyperEVM as a peer on the NTT manager
// and transceiver deployed by proposal 4; both are owned by the Timelock, so only governance can
// do it, and without it UNI burned on HyperEVM never releases on Ethereum. The HyperEVM half
// travels over Wormhole and turns on v2, v3, and v4 fees.
//
// Each half has preconditions on its own chain, so this script has an entry point per chain.
//
// 1. `preflight()` against HyperEVM asserts the receiver trusts the Ethereum sender and holds the
//    authority each remote call needs. A failure here surfaces before the vote instead of when the
//    message is relayed after it:
//
//    forge script script/proposal-7/HyperEVMFees.s.sol --sig "preflight()" --rpc-url hyperevm
//
// 2. `run()` against Ethereum asserts the Ethereum-side state, then writes the proposal for
//    Seatbelt. Both prerequisite scripts must have run on HyperEVM first, since this reads their
//    deployments out of the record:
//
//    forge script script/proposal-7/HyperEVMFees.s.sol --rpc-url mainnet
//
// ---
//
// Wormhole does not deliver the HyperEVM message. After the proposal executes, someone must fetch
// the VAA for action 02 from Wormhole's API and call `receiveMessage` on the HyperEVM receiver;
// proposal 4 did this with a finalizer script carrying the VAA bytes. A third-party relayer may
// deliver it first, in which case a later attempt reverts as a replay even though the message ran.
//
contract HyperEVMFees is Script {
  Recorder internal recorder;
  Uniswap internal uniswap;

  function run() external {
    Constants.smokeCheck();

    uniswap.loadLatest();
    recorder.initialize({scriptName: Constants.RECORD_NAME});

    require(block.chainid == ChainId.Ethereum, "not Ethereum");

    _checkEthereum();

    // Both Wormhole publications below must carry exactly the core bridge's fee. It is zero today
    // and read here rather than assumed; if it changes between proposal and execution, execution
    // fails and the proposal has to be re-made, which no script can prevent.
    uint256 messageFee = IWormhole(uniswap.ethereum.bridge.wormholeCore).messageFee();

    uint256 chainId = Constants.HyperEVM.CHAIN_ID;

    address hyperEvmNttManager =
      recorder.read({chainId: chainId, deploymentName: Constants.Records.NTT_MANAGER});
    address hyperEvmTransceiver =
      recorder.read({chainId: chainId, deploymentName: Constants.Records.WORMHOLE_TRANSCEIVER});
    address tokenJar =
      recorder.read({chainId: chainId, deploymentName: Constants.Records.TOKEN_JAR});
    address v3OpenFeeAdapter =
      recorder.read({chainId: chainId, deploymentName: Constants.Records.V3_OPEN_FEE_ADAPTER});
    address v4FeeAdapter =
      recorder.read({chainId: chainId, deploymentName: Constants.Records.V4_FEE_ADAPTER});

    // ---------------------------------------------------------------------------------------------
    // Action 00
    //
    // Set the HyperEVM `WormholeTransceiver` proxy as a peer on the Ethereum
    // `WormholeTransceiver` proxy.
    //
    // `setWormholePeer` is payable because it publishes a Wormhole message announcing the
    // registration.
    //
    // Parameters:
    //
    // - `target`: Ethereum WormholeTransceiver proxy, owned by the Timelock.
    // - `value`: Wormhole core message fee, read above.
    // - `peerChainId`: Wormhole-defined HyperEVM Chain Id.
    // - `peerContract`: HyperEVM WormholeTransceiver proxy.
    //
    Call memory setEthereumTransceiverPeer = Call({
      target: uniswap.ethereum.wormholeTransceiver,
      value: messageFee,
      data: abi.encodeCall(
        IWormholeTransceiver.setWormholePeer,
        (
          Constants.HyperEVM.WORMHOLE_CHAIN_ID,
          WormholeEncoder.toWormholeFormat(hyperEvmTransceiver)
        )
      )
    });

    // ---------------------------------------------------------------------------------------------
    // Action 01
    //
    // Set the HyperEVM `NttManager` proxy as a peer on the Ethereum `NttManager` proxy.
    //
    // Parameters:
    //
    // - `target`: Ethereum NttManager proxy, owned by the Timelock.
    // - `peerChainId`: Wormhole-defined HyperEVM Chain Id.
    // - `peerContract`: HyperEVM NttManager proxy.
    // - `decimals`: UNI decimals on HyperEVM.
    // - `inboundLimit`: Set to zero when rate limiter is disabled, matching BNB Chain and Polygon.
    //
    Call memory setEthereumNttManagerPeer = Call({
      target: uniswap.ethereum.nttManager,
      value: 0,
      data: abi.encodeCall(
        INttManagerPeers.setPeer,
        (
          Constants.HyperEVM.WORMHOLE_CHAIN_ID,
          WormholeEncoder.toWormholeFormat(hyperEvmNttManager),
          18,
          0
        )
      )
    });

    // ---------------------------------------------------------------------------------------------
    // Action 02
    //
    // Turn on v2, v3, and v4 fees on HyperEVM, as one Wormhole message carrying the three remote
    // calls below.
    //
    // All three run from the `UniswapWormholeMessageReceiver` on HyperEVM. Each depends on the
    // receiver already holding the authority named in its block; that handoff from the deploying
    // team is a prerequisite for this proposal, not part of it, and `preflight()` asserts it.

    // Remote call 00
    //
    // Set `UniswapV2Factory.feeTo` to `TokenJar`. Requires the receiver to be the factory's
    // `feeToSetter`.
    //
    // Parameters:
    //
    // - `target`: HyperEVM Uniswap V2 Factory.
    // - `_feeTo`: HyperEVM TokenJar.
    //
    Call memory setV2FeeTo = Call({
      target: Constants.HyperEVM.V2_FACTORY,
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
    // - `target`: HyperEVM Uniswap V3 Factory.
    // - `_owner`: HyperEVM V3OpenFeeAdapter.
    //
    Call memory setV3Owner = Call({
      target: Constants.HyperEVM.V3_FACTORY,
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
    // - `target`: HyperEVM Uniswap V4 Pool Manager.
    // - `controller`: HyperEVM V4FeeAdapter.
    //
    Call memory setV4FeeController = Call({
      target: Constants.HyperEVM.POOL_MANAGER,
      value: 0,
      data: abi.encodeCall(IPoolManager.setProtocolFeeController, (v4FeeAdapter))
    });

    // The `sendMessage` envelope, see `_encodeWormhole`:
    //
    // - `value`: Wormhole core message fee, read above.
    // - `targets`, `values`, `calldatas`: Remote calls 00, 01, and 02, split into parallel arrays.
    // - `messageReceiver`: HyperEVM `UniswapWormholeMessageReceiver`, which executes them.
    // - `receiverChainId`: Wormhole-defined HyperEVM Chain Id.
    //
    Call[] memory hyperEvmCalls = LibCall.newCalls([setV2FeeTo, setV3Owner, setV4FeeController]);

    Call memory activateHyperEvmFees = _encodeWormhole(hyperEvmCalls, messageFee);

    // ---------------------------------------------------------------------------------------------
    // Output
    //
    // The inputs to `GovernorBravo.propose(targets, values, signatures, datas, description)`,
    // bundling the three actions above, written to disk for Seatbelt. This script does not
    // broadcast anything; the `propose` call itself is made separately.
    //
    // Parameters:
    //
    // - `targets`, `values`, `signatures`, `datas`: Actions 00, 01, and 02, split into parallel
    //   arrays by `Proposal.toGovernorBravoInputs()`.
    // - `description`: `DESCRIPTION`, which is still placeholder text.
    //
    Proposal memory hyperEvmFeeProposal = Proposal({
      description: DESCRIPTION,
      calls: LibCall.newCalls(
        [setEthereumTransceiverPeer, setEthereumNttManagerPeer, activateHyperEvmFees]
      )
    });

    vm.createDir("./out/.seatbelt/", true);
    vm.writeFile({
      path: "./out/.seatbelt/HyperEVMFeeProposal.json",
      data: GovernanceSeatbelt.toJson({
        proposal: hyperEvmFeeProposal, governorBravo: uniswap.ethereum.governorBravo
      })
    });
  }

  /// @dev Asserts HyperEVM is in the state action 02 assumes: the receiver trusts the Ethereum
  /// sender, and it holds the authority each remote call needs. Run against HyperEVM.
  function preflight() external view {
    Constants.smokeCheck();

    require(block.chainid == Constants.HyperEVM.CHAIN_ID, "not HyperEVM");

    address receiver = Constants.HyperEVM.WORMHOLE_RECEIVER;

    require(
      IUniswapWormholeMessageReceiver(receiver).messageSender()
        == WormholeEncoder.toWormholeFormat(Constants.Ethereum.WORMHOLE_SENDER),
      "receiver.messageSender"
    );
    require(
      IUniswapWormholeMessageReceiver(receiver).ETHEREUM_CHAIN_ID() == WormholeChainId.Ethereum,
      "receiver.ethereumChainId"
    );

    require(
      IUniswapV2Factory(Constants.HyperEVM.V2_FACTORY).feeToSetter() == receiver,
      "v2Factory.feeToSetter"
    );
    require(IUniswapV3Factory(Constants.HyperEVM.V3_FACTORY).owner() == receiver, "v3Factory.owner");
    require(IPoolManager(Constants.HyperEVM.POOL_MANAGER).owner() == receiver, "poolManager.owner");
  }

  /// @dev Asserts Ethereum is in the state actions 00 through 02 assume: every target answers to
  /// the Timelock, and neither NTT contract knows HyperEVM yet. `setWormholePeer` reverts on an
  /// existing peer and `setPeer` silently overwrites one, so both are checked up front.
  function _checkEthereum() internal view {
    address timelock = uniswap.ethereum.timelock;
    uint16 hyperEvm = Constants.HyperEVM.WORMHOLE_CHAIN_ID;

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
    require(transceiver.getWormholePeer(hyperEvm) == bytes32(0), "wormholeTransceiver.peer set");

    // NttManager
    INttManagerPeers nttManager = INttManagerPeers(uniswap.ethereum.nttManager);

    require(nttManager.owner() == timelock, "nttManager.owner");
    require(nttManager.getPeer(hyperEvm).peerAddress == bytes32(0), "nttManager.peer set");
  }

  /// @dev Encodes a batch of HyperEVM calls as a single Wormhole message from the Timelock.
  /// @dev This is `WormholeEncoder.encode` with the chain id supplied directly. The encoder maps
  /// an EIP-155 chain id to a Wormhole one through `WormholeChainId`, which does not know HyperEVM
  /// yet; that mapping lands in govkit once this proposal has executed, at which point this helper
  /// collapses back to a `WormholeEncoder.encode` call.
  function _encodeWormhole(Call[] memory remoteCalls, uint256 value)
    internal
    pure
    returns (Call memory)
  {
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
        (
          targets,
          values,
          datas,
          Constants.HyperEVM.WORMHOLE_RECEIVER,
          Constants.HyperEVM.WORMHOLE_CHAIN_ID
        )
      )
    });
  }
}
