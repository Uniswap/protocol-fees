// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {Proposal} from "govkit/types/Proposal.sol";
import {Call} from "govkit/types/Call.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {GovernanceSeatbelt} from "govkit/forge/GovernanceSeatbelt.sol";
import {L1CrossDomainMessengerEncoder} from "govkit/bridges/L1CrossDomainMessengerEncoder.sol";
import {InboxEncoder} from "govkit/bridges/InboxEncoder.sol";
import {IPoolManager} from "govkit/interfaces/IPoolManager.sol";

import {V4FeeAdapter} from "../../src/feeAdapters/V4FeeAdapter.sol";

import {V4Accounts, selectChain, v4Accounts} from "../proposal-104/params/Chains.sol";
import {loadPolicyParams} from "../proposal-104/params/PolicyParams.sol";
import {checkNewPolicy} from "../proposal-104/PolicyCheck.sol";
import {readPolicyDeployment} from "../proposal-104/prereq/DeployV4FeePolicy.s.sol";
import {
  ARB_SYS,
  checkCrossChainAccount,
  checkInboxEthereum,
  checkOPStackMessengerEthereum
} from "../proposal-104/BridgeChecks.sol";

import {DESCRIPTION} from "./Description.sol";
import {
  RECORD_NAME,
  POLICY_PARAMS_JSON,
  V4_FEE_ADAPTER_RECORD,
  chains,
  l1Messenger,
  tokenJar
} from "./params/Constants.sol";
import {readRecord} from "../proposal-104/params/Constants.sol";
import {checkNewAdapter} from "./AdapterCheck.sol";
import {
  buildUpdateStableHookFeeConfigCall,
  checkStableHookAfter,
  checkStableHookBefore
} from "./StableHookUpdate.sol";

/// @notice Returns the proposal's calls: one per chain in the order of `chains`, then the Arbitrum
///         StablePairHook fee config update.
/// @dev A free function, so the fork tests, and callers outside this repo, build the same calls
///      the script writes without deploying the script. Assumes an initialized `recorder`.
function buildProposal(Uniswap storage uniswap, Recorder storage recorder)
  view
  returns (Proposal memory proposal)
{
  proposal.description = DESCRIPTION;
  proposal.calls = new Call[](chains().length + 1);

  // ---------------------------------------------------------------------------------------------
  // Actions 00 to 04
  //
  // For each chain, set the PoolManager's `protocolFeeController` to the new adapter. Requires the
  // chain's CrossChainAccount to be the PoolManager's `owner`.
  //
  // The `sendMessage` envelope, see `L1CrossDomainMessengerEncoder.encode`:
  //
  // - `target`: the chain's L1CrossDomainMessenger on Ethereum.
  // - `_target`: the chain's CrossChainAccount, which runs the call through `forward`.
  // - `_minGasLimit`: the encoder's default, 200,000.
  //
  for (uint256 i; i < chains().length; i++) {
    uint256 chainId = chains()[i];
    V4Accounts memory accounts = v4Accounts(uniswap, chainId);
    address adapter = readRecord(recorder, chainId, V4_FEE_ADAPTER_RECORD);
    require(adapter != address(0), "recorded V4FeeAdapter is zero");
    proposal.calls[i] = L1CrossDomainMessengerEncoder.encode({
      l1CrossDomainMessenger: l1Messenger(uniswap, chainId),
      crossChainAccount: accounts.governanceExecutor,
      remoteCall: Call({
        target: accounts.poolManager,
        value: 0,
        data: abi.encodeCall(IPoolManager.setProtocolFeeController, (adapter))
      })
    });
  }

  // ---------------------------------------------------------------------------------------------
  // Action 05
  //
  // Set the `optimalFeeE6` of Arbitrum's StablePairHook pools, in a retryable ticket that runs from
  // the Timelock's alias, which holds the hook's `CONFIG_MANAGER_ROLE`.
  //
  proposal.calls[chains().length] = buildUpdateStableHookFeeConfigCall(uniswap);
}

/// @title Proposal105
/// @notice Turns on v4 fees on Celo, Soneium, X Layer, World Chain and Zora, and sets the
///         `optimalFeeE6` of Arbitrum's StablePairHook pools. Actions 00 to 04 each send one
///         message through the chain's L1CrossDomainMessenger; the chain's CrossChainAccount owns
///         the PoolManager, and runs the message's one call: `setProtocolFeeController` with the
///         new `V4FeeAdapter`. Pools pay no protocol fee until someone calls
///         `batchTriggerFeeUpdate` with their keys. Action 05 sends a retryable ticket through
///         Arbitrum's Inbox that updates the StablePairHook's fee configs.
/// @dev `Index.md` in this directory gives the steps to deploy, check, write and execute the
///      proposal.
contract Proposal105 is Script {
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

    string memory path = "./out/.seatbelt/Proposal105.json";
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
  ///         each of the five chains and Arbitrum, each at the chain's latest block.
  /// @dev Run without `--rpc-url`; it forks each chain through its `foundry.toml` alias, and
  ///      reverts if an alias reaches another chain.
  function preflight() external {
    selectChain(ChainId.Ethereum);
    preflightEthereum();
    uint256[5] memory list = chains();
    for (uint256 i; i < list.length; i++) {
      selectChain(list[i]);
      preflightRemote();
    }
    selectChain(ChainId.Arbitrum);
    preflightRemote();
  }

  /// @notice Runs {postflightRemote} on a fork of each of the five chains and Arbitrum, each at the
  ///         chain's latest block.
  /// @dev Run without `--rpc-url`, once every action's message has run.
  function postflight() external {
    uint256[5] memory list = chains();
    for (uint256 i; i < list.length; i++) {
      selectChain(list[i]);
      postflightRemote();
    }
    selectChain(ChainId.Arbitrum);
    postflightRemote();
  }

  /// @notice Runs {preflightEthereum} at block `blockNumber`.
  /// @dev Pin the fork to the same block:
  ///      `--sig "preflightEthereum(uint256)" $B --rpc-url mainnet --fork-block-number $B`.
  function preflightEthereum(uint256 blockNumber) public view {
    require(block.number == blockNumber, "block number");
    preflightEthereum();
  }

  /// @notice Asserts that each chain's L1CrossDomainMessenger is unpaused and reaches its chain,
  ///         and that Arbitrum's Inbox is unpaused and reaches Arbitrum.
  /// @dev Run against Ethereum.
  function preflightEthereum() public view {
    require(block.chainid == ChainId.Ethereum, "not Ethereum");
    console.log("preflightEthereum Proposal105 at block", block.number);

    for (uint256 i; i < chains().length; i++) {
      checkOPStackMessengerEthereum(
        l1Messenger(uniswap, chains()[i]), chains()[i], vm.toString(chains()[i])
      );
    }
    checkInboxEthereum(uniswap.ethereum.bridge.arbitrum, ChainId.Arbitrum, "arbitrum");
  }

  /// @notice Runs {preflightRemote} at block `blockNumber`.
  /// @dev Pin the fork to the same block:
  ///      `--sig "preflightRemote(uint256)" $B --rpc-url <chain> --fork-block-number $B`.
  function preflightRemote(uint256 blockNumber) public {
    require(_blockNumber() == blockNumber, "block number");
    preflightRemote();
  }

  /// @notice Asserts that the chain is in the state its action assumes. On the five chains: the
  ///         Timelock's messages reach the CrossChainAccount, the CrossChainAccount owns the
  ///         PoolManager, the PoolManager has no fee controller, and the recorded adapter and
  ///         policy pass {checkNewAdapter} and {checkNewPolicy}. On Arbitrum: the StablePairHook
  ///         passes {checkStableHookBefore}, and the chain's base fee is under the retryable
  ///         ticket's gas bid.
  /// @dev Run against each of the five chains and Arbitrum.
  function preflightRemote() public {
    console.log("preflightRemote Proposal105 on chain", block.chainid, "at block", _blockNumber());
    if (block.chainid == ChainId.Arbitrum) {
      checkStableHookBefore(uniswap);
      // Assert the chain's base fee is under the gas bid that `InboxEncoder.encode` gives action
      // 05's retryable ticket, so Arbitrum redeems the ticket when it arrives.
      require(block.basefee <= InboxEncoder.MAX_FEE_PER_GAS, "retryable.maxFeePerGas");
      return;
    }
    recorder.initialize({scriptName: _recordName()});

    V4Accounts memory accounts = v4Accounts(uniswap, block.chainid);
    IPoolManager poolManager = IPoolManager(accounts.poolManager);

    checkCrossChainAccount(
      accounts.governanceExecutor, l1Messenger(uniswap, block.chainid), uniswap.ethereum.timelock
    );
    require(poolManager.owner() == accounts.governanceExecutor, "poolManager.owner");
    require(poolManager.protocolFeeController() == address(0), "poolManager.protocolFeeController");

    address policy = address(readPolicyDeployment(recorder, block.chainid).policy);
    checkNewAdapter(
      V4FeeAdapter(readRecord(recorder, block.chainid, V4_FEE_ADAPTER_RECORD)),
      accounts.poolManager,
      tokenJar(uniswap, block.chainid),
      policy,
      accounts.governanceExecutor
    );
    checkNewPolicy(
      readPolicyDeployment(recorder, block.chainid),
      loadPolicyParams(_paramsPath(), block.chainid),
      accounts.governanceExecutor
    );
  }

  /// @notice Asserts that the PoolManager's fee controller is the recorded adapter, or on Arbitrum
  ///         that the StablePairHook passes {checkStableHookAfter}.
  /// @dev The fork tests call it after they relay each message. After a message runs onchain, run
  ///      it against the message's chain.
  function postflightRemote() public {
    console.log("postflightRemote Proposal105 on chain", block.chainid, "at block", _blockNumber());
    if (block.chainid == ChainId.Arbitrum) {
      checkStableHookAfter();
      console.log("stable hook optimalFeeE6 updated");
      return;
    }
    recorder.initialize({scriptName: _recordName()});

    address adapter = readRecord(recorder, block.chainid, V4_FEE_ADAPTER_RECORD);
    require(adapter.code.length != 0, "adapter.code");
    require(
      IPoolManager(v4Accounts(uniswap, block.chainid).poolManager).protocolFeeController()
        == adapter,
      "poolManager.protocolFeeController"
    );
    console.log("fee controller set", adapter);
  }

  /// @notice Returns the chain's block number. On Arbitrum `block.number` is an Ethereum block
  ///         number, so read Arbitrum's own from ArbSys.
  function _blockNumber() internal view returns (uint256) {
    if (block.chainid == ChainId.Arbitrum) return ARB_SYS.arbBlockNumber();
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
