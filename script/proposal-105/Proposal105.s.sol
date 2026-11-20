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
import {IPoolManager} from "govkit/interfaces/IPoolManager.sol";

import {V4FeeAdapter} from "../../src/feeAdapters/V4FeeAdapter.sol";

import {V4Accounts, v4Accounts} from "../proposal-104/params/Chains.sol";
import {loadPolicyParams} from "../proposal-104/params/PolicyParams.sol";
import {checkNewPolicy} from "../proposal-104/PolicyCheck.sol";
import {readPolicyDeployment} from "../proposal-104/prereq/DeployV4FeePolicy.s.sol";
import {
  checkCrossChainAccount,
  checkOPStackMessengerEthereum
} from "../proposal-104/BridgeChecks.sol";

import {DESCRIPTION} from "./Description.sol";
import {
  RECORD_NAME,
  POLICY_PARAMS_JSON,
  V4_FEE_ADAPTER_RECORD,
  chains,
  l1Messenger,
  tokenJar,
  v3OpenFeeAdapter
} from "./params/Constants.sol";
import {checkNewAdapter} from "./AdapterCheck.sol";

// -------------------------------------------------------------------------------------------------
// NOTICE:
//
// The proposal turns on v4 fees on Celo, Soneium, X Layer, World Chain and Zora. Each action is
// one Ethereum call that sends one message through the chain's L1CrossDomainMessenger. The chain's
// CrossChainAccount owns the PoolManager, and runs the message's one call:
// `setProtocolFeeController` with the new `V4FeeAdapter`. Pools pay no protocol fee until someone
// calls `batchTriggerFeeUpdate`
// with their keys.
//
// 1. Run `prereq/DeployV4FeeAdapter.s.sol` on each chain. It records the new adapters and
//    policies in `.records/Proposal105.json`, where `buildProposal` reads them.
// 2. Run `preflightRemote()` against each chain before proposing:
//
//    forge script script/proposal-105/Proposal105.s.sol --sig "preflightRemote()" \
//      --rpc-url <chain>
//
// 3. `run()` against Ethereum runs `preflightEthereum()`, then writes the proposal for Seatbelt:
//
//    forge script script/proposal-105/Proposal105.s.sol --rpc-url mainnet
//
// 4. The OP Stack bridges relay each message by themselves once the proposal executes. After each
//    message runs, run `postflightRemote()` against its chain.
//

/// @notice Returns the proposal's calls, one per chain in the order of `chains`.
/// @dev A free function, so the fork tests, and callers outside this repo, build the same calls
///      the script writes without deploying the script. Assumes an initialized `recorder`.
function buildProposal(Uniswap storage uniswap, Recorder storage recorder)
  view
  returns (Proposal memory proposal)
{
  proposal.description = DESCRIPTION;
  proposal.calls = new Call[](chains().length);

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
    address adapter = recorder.read(chainId, V4_FEE_ADAPTER_RECORD);
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
}

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

  /// @notice Runs {preflightEthereum} at block `blockNumber`.
  /// @dev Pin the fork to the same block:
  ///      `--sig "preflightEthereum(uint256)" $B --rpc-url mainnet --fork-block-number $B`.
  function preflightEthereum(uint256 blockNumber) public view {
    require(block.number == blockNumber, "block number");
    preflightEthereum();
  }

  /// @notice Asserts that each chain's L1CrossDomainMessenger is unpaused and reaches an OP Stack
  ///         chain.
  /// @dev Run against Ethereum.
  function preflightEthereum() public view {
    require(block.chainid == ChainId.Ethereum, "not Ethereum");
    console.log("preflightEthereum Proposal105 at block", block.number);

    for (uint256 i; i < chains().length; i++) {
      checkOPStackMessengerEthereum(
        l1Messenger(uniswap, chains()[i]), chains()[i], vm.toString(chains()[i])
      );
    }
  }

  /// @notice Runs {preflightRemote} at block `blockNumber`.
  /// @dev Pin the fork to the same block:
  ///      `--sig "preflightRemote(uint256)" $B --rpc-url <chain> --fork-block-number $B`.
  function preflightRemote(uint256 blockNumber) public {
    require(block.number == blockNumber, "block number");
    preflightRemote();
  }

  /// @notice Asserts that the chain is in the state its action assumes: the Timelock's messages
  ///         reach the CrossChainAccount, the CrossChainAccount owns the PoolManager, the
  ///         PoolManager has no fee controller, and the recorded adapter and policy pass
  ///         {checkNewAdapter} and {checkNewPolicy}.
  /// @dev Run against each of the five chains.
  function preflightRemote() public {
    recorder.initialize({scriptName: _recordName()});
    console.log("preflightRemote Proposal105 on chain", block.chainid, "at block", block.number);

    V4Accounts memory accounts = v4Accounts(uniswap, block.chainid);
    IPoolManager poolManager = IPoolManager(accounts.poolManager);

    checkCrossChainAccount(
      accounts.governanceExecutor, l1Messenger(uniswap, block.chainid), uniswap.ethereum.timelock
    );
    require(poolManager.owner() == accounts.governanceExecutor, "poolManager.owner");
    require(poolManager.protocolFeeController() == address(0), "poolManager.protocolFeeController");

    address policy = address(readPolicyDeployment(recorder, block.chainid).policy);
    checkNewAdapter(
      V4FeeAdapter(recorder.read(block.chainid, V4_FEE_ADAPTER_RECORD)),
      accounts.poolManager,
      tokenJar(uniswap, block.chainid),
      v3OpenFeeAdapter(uniswap, block.chainid),
      policy,
      accounts.governanceExecutor
    );
    checkNewPolicy(
      readPolicyDeployment(recorder, block.chainid),
      loadPolicyParams(_paramsPath(), block.chainid),
      accounts.governanceExecutor
    );
  }

  /// @notice Asserts that the PoolManager's fee controller is the recorded adapter.
  /// @dev The fork tests call it after they relay each message. After a message runs onchain, run
  ///      it against the message's chain.
  function postflightRemote() public {
    recorder.initialize({scriptName: _recordName()});
    console.log("postflightRemote Proposal105 on chain", block.chainid, "at block", block.number);

    address adapter = recorder.read(block.chainid, V4_FEE_ADAPTER_RECORD);
    require(adapter.code.length != 0, "adapter.code");
    require(
      IPoolManager(v4Accounts(uniswap, block.chainid).poolManager).protocolFeeController()
        == adapter,
      "poolManager.protocolFeeController"
    );
    console.log("fee controller set", adapter);
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
