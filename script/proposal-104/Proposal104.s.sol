// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {Proposal} from "govkit/types/Proposal.sol";
import {Call, LibCall} from "govkit/types/Call.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {GovernanceSeatbelt} from "govkit/forge/GovernanceSeatbelt.sol";
import {InboxEncoder} from "govkit/bridges/InboxEncoder.sol";
import {L1CrossDomainMessengerEncoder} from "govkit/bridges/L1CrossDomainMessengerEncoder.sol";
import {WormholeEncoder} from "govkit/bridges/WormholeEncoder.sol";
import {FxRootEncoder} from "govkit/bridges/FxRootEncoder.sol";
import {IWormholeSender} from "govkit/interfaces/bridges/IWormholeSender.sol";
import {IPoolManager} from "govkit/interfaces/IPoolManager.sol";

import {IV4FeeAdapter} from "../../src/interfaces/IV4FeeAdapter.sol";
import {IV4FeePolicy} from "../../src/interfaces/IV4FeePolicy.sol";
import {Owned} from "solmate/src/auth/Owned.sol";

import {IWormhole} from "../proposal-7/Interfaces.sol";
import {encodeWormhole} from "../proposal-7/ArcFees.s.sol";
import {Arc, Ethereum as Proposal7Ethereum} from "../proposal-7/params/Constants.sol";
import {IFxRoot} from "govkit/interfaces/bridges/IFxRoot.sol";

import {DESCRIPTION} from "./Description.sol";
import {
  RECORD_NAME,
  POLICY_PARAMS_JSON,
  POLYGON_FX_CHILD,
  Records,
  chains,
  readRecord,
  replacedV4FeePolicy,
  v4FeeAdapter
} from "./params/Constants.sol";
import {V4Accounts, selectChain, v4Accounts} from "./params/Chains.sol";
import {loadPolicyParams} from "./params/PolicyParams.sol";
import {checkNewPolicy} from "./PolicyCheck.sol";
import {readPolicyDeployment} from "./prereq/DeployV4FeePolicy.s.sol";
import {
  ARB_SYS,
  checkCrossChainAccount,
  checkEthereumProxy,
  checkInboxEthereum,
  checkBNBChainWormholeReceiver,
  checkOPStackMessengerEthereum,
  checkWormholeReceiver
} from "./BridgeChecks.sol";

/// @notice Returns the proposal's calls.
/// @dev A free function, so the fork tests, and callers outside this repo, build the same calls
///      the script writes without deploying the script. Assumes an Ethereum fork and an
///      initialized `recorder`.
function buildProposal(Uniswap storage uniswap, Recorder storage recorder)
  view
  returns (Proposal memory)
{
  // Read the Wormhole message fee rather than assume it. It is zero when proposal 7 executed. If
  // it changes between proposal and execution, execution reverts and the proposal must be made
  // again.
  uint256 messageFee = IWormhole(uniswap.ethereum.bridge.wormholeCore).messageFee();

  Call[] memory calls = new Call[](8);

  // ---------------------------------------------------------------------------------------------
  // Action 00
  //
  // Set the Ethereum adapter's policy. The Timelock owns the adapter.
  //
  calls[0] = _setPolicyCall(recorder, ChainId.Ethereum);

  // ---------------------------------------------------------------------------------------------
  // Action 01
  //
  // Set the Arbitrum adapter's policy, in a retryable ticket that runs from the aliased Timelock.
  //
  calls[1] = InboxEncoder.encode({
    inbox: uniswap.ethereum.bridge.arbitrum,
    timelock: uniswap.ethereum.timelock,
    remoteCall: _setPolicyCall(recorder, ChainId.Arbitrum)
  });

  // ---------------------------------------------------------------------------------------------
  // Actions 02 and 03
  //
  // Set the Base and OP Mainnet adapters' policies, each in a message that the chain's
  // CrossChainAccount runs.
  //
  calls[2] = L1CrossDomainMessengerEncoder.encode({
    l1CrossDomainMessenger: uniswap.ethereum.bridge.base,
    crossChainAccount: uniswap.base.crossChainAccount,
    remoteCall: _setPolicyCall(recorder, ChainId.Base)
  });
  calls[3] = L1CrossDomainMessengerEncoder.encode({
    l1CrossDomainMessenger: uniswap.ethereum.bridge.optimism,
    crossChainAccount: uniswap.optimism.crossChainAccount,
    remoteCall: _setPolicyCall(recorder, ChainId.Optimism)
  });

  // ---------------------------------------------------------------------------------------------
  // Action 04
  //
  // Set the BNB Chain adapter's policy, in a Wormhole message that the chain's
  // UniswapWormholeMessageReceiver runs.
  //
  calls[4] = WormholeEncoder.encode({
    sourceSender: uniswap.ethereum.bridge.bnbChain,
    remoteReceiver: uniswap.bnbChain.wormholeReceiver,
    chainId: ChainId.BNBChain,
    value: messageFee,
    remoteCalls: LibCall.newCalls([_setPolicyCall(recorder, ChainId.BNBChain)])
  });

  // ---------------------------------------------------------------------------------------------
  // Action 05
  //
  // Set the Polygon adapter's policy, in a message that the chain's FxChild receiver runs.
  //
  calls[5] = FxRootEncoder.encode({
    fxRoot: uniswap.ethereum.bridge.polygon,
    fxReceiver: uniswap.polygon.fxReceiver,
    remoteCalls: LibCall.newCalls([_setPolicyCall(recorder, ChainId.Polygon)])
  });

  // ---------------------------------------------------------------------------------------------
  // Action 06
  //
  // Set the Robinhood Chain adapter's policy, in a retryable ticket that runs from the aliased
  // Timelock.
  //
  calls[6] = InboxEncoder.encode({
    inbox: uniswap.ethereum.bridge.robinhood,
    timelock: uniswap.ethereum.timelock,
    remoteCall: _setPolicyCall(recorder, ChainId.Robinhood)
  });

  // ---------------------------------------------------------------------------------------------
  // Action 07
  //
  // Set the Arc adapter's policy, in a Wormhole message that the chain's
  // UniswapWormholeMessageReceiver runs. govkit's Wormhole encoder does not know Arc, so use
  // proposal 7's encoder.
  //
  calls[7] = encodeWormhole(LibCall.newCalls([_setPolicyCall(recorder, Arc.CHAIN_ID)]), messageFee);

  return Proposal({description: DESCRIPTION, calls: calls});
}

/// @notice Returns the call that sets the new policy on the adapter of `chainId`.
function _setPolicyCall(Recorder storage recorder, uint256 chainId) view returns (Call memory) {
  address policy = readRecord(recorder, chainId, Records.V4_FEE_POLICY);
  require(policy != address(0), "recorded V4FeePolicy is zero");
  return Call({
    target: v4FeeAdapter(chainId),
    value: 0,
    data: abi.encodeCall(IV4FeeAdapter.setPolicy, (IV4FeePolicy(policy)))
  });
}

/// @title Proposal104
/// @notice Replaces the `V4FeePolicy` of the `V4FeeAdapter` on eight chains. Each action is one
///         Ethereum call that calls `setPolicy` on one chain's adapter, through that chain's
///         governance route. The adapters stay; existing pools keep their protocol fee until
///         someone calls `batchTriggerFeeUpdate` with their keys.
/// @dev `Index.md` in this directory gives the steps to deploy, check, write and execute the
///      proposal.
contract Proposal104 is Script {
  Uniswap internal uniswap;
  Recorder internal recorder;

  constructor() {
    uniswap.loadLatest();
  }

  /// @notice Asserts the Ethereum state, then writes the proposal for Governance Seatbelt.
  /// @dev Does not broadcast a transaction. Run against Ethereum.
  function run() external {
    preflightEthereum();
    recorder.initialize({scriptName: _recordName()});

    string memory path = "./out/.seatbelt/Proposal104.json";
    vm.createDir("./out/.seatbelt/", true);
    vm.writeFile({
      path: path,
      data: GovernanceSeatbelt.toJson({
        proposal: buildProposal(uniswap, recorder), governorBravo: uniswap.ethereum.governorBravo
      })
    });
    console.log("wrote", path);
  }

  /// @notice Runs {preflightEthereum} on a fork of Ethereum, then {preflightRemote} on a fork of
  ///         each of the eight chains, each at the chain's latest block.
  /// @dev Run without `--rpc-url`; it forks each chain through its `foundry.toml` alias, and
  ///      reverts if an alias reaches another chain.
  function preflight() external {
    selectChain(ChainId.Ethereum);
    preflightEthereum();
    uint256[8] memory list = chains();
    for (uint256 i; i < list.length; i++) {
      selectChain(list[i]);
      preflightRemote();
    }
  }

  /// @notice Runs {postflightRemote} on a fork of each of the eight chains, each at the chain's
  ///         latest block.
  /// @dev Run without `--rpc-url`, once every action's message has run.
  function postflight() external {
    uint256[8] memory list = chains();
    for (uint256 i; i < list.length; i++) {
      selectChain(list[i]);
      postflightRemote();
    }
  }

  /// @notice Runs {preflightEthereum} at block `blockNumber`.
  /// @dev Pin the fork to the same block:
  ///      `--sig "preflightEthereum(uint256)" $B --rpc-url mainnet --fork-block-number $B`.
  function preflightEthereum(uint256 blockNumber) public view {
    require(block.number == blockNumber, "block number");
    preflightEthereum();
  }

  /// @notice Asserts that each Ethereum route the actions use delivers to its chain.
  /// @dev Run against Ethereum.
  function preflightEthereum() public view {
    require(block.chainid == ChainId.Ethereum, "not Ethereum");
    console.log("preflightEthereum Proposal104 at block", block.number);

    checkInboxEthereum(uniswap.ethereum.bridge.arbitrum, ChainId.Arbitrum, "arbitrum");
    checkInboxEthereum(uniswap.ethereum.bridge.robinhood, ChainId.Robinhood, "robinhood");
    checkOPStackMessengerEthereum(uniswap.ethereum.bridge.base, ChainId.Base, "base");
    checkOPStackMessengerEthereum(uniswap.ethereum.bridge.optimism, ChainId.Optimism, "optimism");

    // Assert actions 04 and 07 use the same Wormhole sender, and that the Timelock owns it.
    require(
      Proposal7Ethereum.WORMHOLE_SENDER == uniswap.ethereum.bridge.bnbChain,
      "wormholeSender: proposal 7 constant differs from govkit"
    );
    require(
      IWormholeSender(uniswap.ethereum.bridge.bnbChain).owner() == uniswap.ethereum.timelock,
      "wormholeSender.owner"
    );

    // Assert FxRoot sends action 05 to the FxChild that Polygon's `EthereumProxy` accepts.
    require(
      IFxRoot(uniswap.ethereum.bridge.polygon).fxChild() == POLYGON_FX_CHILD, "fxRoot.fxChild"
    );
  }

  /// @notice Runs {preflightRemote} at block `blockNumber`.
  /// @dev Pin the fork to the same block:
  ///      `--sig "preflightRemote(uint256)" $B --rpc-url <chain> --fork-block-number $B`.
  function preflightRemote(uint256 blockNumber) public {
    require(_blockNumber() == blockNumber, "block number");
    preflightRemote();
  }

  /// @notice Asserts that the chain is in the state its action assumes: the route delivers the
  ///         Timelock's message to the governance executor, the executor owns the adapter, the
  ///         adapter is the PoolManager's fee controller and still uses the v1 policy, and the
  ///         recorded policy passes {checkNewPolicy}.
  /// @dev Run against each of the eight chains.
  function preflightRemote() public {
    recorder.initialize({scriptName: _recordName()});
    console.log("preflightRemote Proposal104 on chain", block.chainid, "at block", _blockNumber());

    V4Accounts memory accounts = v4Accounts(uniswap, block.chainid);
    address adapter = v4FeeAdapter(block.chainid);

    require(
      IPoolManager(accounts.poolManager).protocolFeeController() == adapter,
      "poolManager.protocolFeeController"
    );
    require(Owned(adapter).owner() == accounts.governanceExecutor, "adapter.owner");
    require(
      address(IV4FeeAdapter(adapter).policy()) == replacedV4FeePolicy(block.chainid),
      "adapter.policy"
    );
    _checkRoute(accounts.governanceExecutor);

    checkNewPolicy(
      readPolicyDeployment(recorder, block.chainid),
      loadPolicyParams(_paramsPath(), block.chainid),
      accounts.governanceExecutor
    );
  }

  /// @notice Asserts that the adapter is still the PoolManager's fee controller and uses the
  ///         recorded policy.
  /// @dev The fork tests call it after they run each action. After a message runs onchain, run it
  ///      against the message's chain.
  function postflightRemote() public {
    recorder.initialize({scriptName: _recordName()});
    console.log("postflightRemote Proposal104 on chain", block.chainid, "at block", _blockNumber());

    address adapter = v4FeeAdapter(block.chainid);
    address policy = readRecord(recorder, block.chainid, Records.V4_FEE_POLICY);
    require(policy.code.length != 0, "policy.code");
    require(
      IPoolManager(v4Accounts(uniswap, block.chainid).poolManager).protocolFeeController()
        == adapter,
      "poolManager.protocolFeeController"
    );
    require(address(IV4FeeAdapter(adapter).policy()) == policy, "adapter.policy");
    console.log("policy set", policy);
  }

  /// @notice Asserts that the chain's route runs the Timelock's messages as `governanceExecutor`,
  ///         and on Arbitrum and Robinhood Chain that the chain's base fee is under the retryable
  ///         ticket's gas bid.
  /// @dev On Ethereum the Timelock calls the adapter itself. On Arbitrum and Robinhood Chain the
  ///      executor is the Timelock's alias, which only the Timelock's retryable tickets run as.
  function _checkRoute(address governanceExecutor) internal view {
    address timelock = uniswap.ethereum.timelock;
    if (block.chainid == ChainId.Base) {
      checkCrossChainAccount(governanceExecutor, uniswap.ethereum.bridge.base, timelock);
    } else if (block.chainid == ChainId.Optimism) {
      checkCrossChainAccount(governanceExecutor, uniswap.ethereum.bridge.optimism, timelock);
    } else if (block.chainid == ChainId.BNBChain) {
      checkBNBChainWormholeReceiver(governanceExecutor, uniswap.ethereum.bridge.bnbChain);
    } else if (block.chainid == Arc.CHAIN_ID) {
      checkWormholeReceiver(
        governanceExecutor, Proposal7Ethereum.WORMHOLE_SENDER, Arc.WORMHOLE_CHAIN_ID
      );
    } else if (block.chainid == ChainId.Polygon) {
      checkEthereumProxy(
        governanceExecutor, POLYGON_FX_CHILD, uniswap.ethereum.bridge.polygon, timelock
      );
    } else if (block.chainid == ChainId.Arbitrum || block.chainid == ChainId.Robinhood) {
      // Assert the chain's base fee is under the gas bid that `InboxEncoder.encode` gives the
      // action's retryable ticket, so the chain redeems the ticket when it arrives.
      require(block.basefee <= InboxEncoder.MAX_FEE_PER_GAS, "retryable.maxFeePerGas");
    }
  }

  /// @notice Returns the chain's block number. On Arbitrum and Robinhood Chain `block.number` is an
  ///         Ethereum block number, so read the chain's own from ArbSys.
  function _blockNumber() internal view returns (uint256) {
    if (block.chainid == ChainId.Arbitrum || block.chainid == ChainId.Robinhood) {
      return ARB_SYS.arbBlockNumber();
    }
    return block.number;
  }

  /// @notice Returns the record file name. Tests override it to read their own deployments.
  function _recordName() internal view virtual returns (string memory) {
    return RECORD_NAME;
  }

  /// @notice Returns the parameter file path.
  function _paramsPath() internal view virtual returns (string memory) {
    return POLICY_PARAMS_JSON;
  }
}
