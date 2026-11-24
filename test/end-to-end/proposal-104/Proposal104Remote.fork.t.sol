// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Vm} from "forge-std/Vm.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {Call, LibCall} from "govkit/types/Call.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {WormholeChainId} from "govkit/constants/WormholeChainId.sol";
import {InboxDecoder} from "govkit/bridges/decoders/InboxDecoder.sol";
import {
  L1CrossDomainMessengerDecoder
} from "govkit/bridges/decoders/L1CrossDomainMessengerDecoder.sol";
import {InboxEncoder} from "govkit/bridges/InboxEncoder.sol";
import {IFxRoot} from "govkit/interfaces/bridges/IFxRoot.sol";

import {
  IWormhole as IWormholeCore
} from "lib/native-token-transfers/evm/lib/wormhole-solidity-sdk/src/interfaces/IWormhole.sol";

import {V4FeeAdapter} from "../../../src/feeAdapters/V4FeeAdapter.sol";
import {Proposal104, buildProposal} from "../../../script/proposal-104/Proposal104.s.sol";
import {DeployV4FeePolicy} from "../../../script/proposal-104/prereq/DeployV4FeePolicy.s.sol";
import {
  POLYGON_FX_CHILD,
  Records,
  chains,
  v4FeeAdapter
} from "../../../script/proposal-104/params/Constants.sol";
import {rpcAlias, v4Accounts} from "../../../script/proposal-104/params/Chains.sol";
import {
  checkInboxEthereum,
  checkOPStackMessengerEthereum
} from "../../../script/proposal-104/BridgeChecks.sol";
import {Arc} from "../../../script/proposal-7/params/Constants.sol";
import {executeAsTimelock} from "../../utils/TimelockExecution.sol";
import {relayOPStackMessage} from "../../utils/OPStackDeposit.sol";
import {V4FeeFixtureTest} from "../../utils/V4FeeFixtureTest.sol";

/// @dev Mainnet block the proposal is built at. `buildProposal` reads the Wormhole message fee
///      from the mainnet core.
uint256 constant MAINNET_BLOCK = 26_450_800;

/// @dev The event Polygon's StateSender emits for each message FxRoot sends.
event StateSynced(uint256 indexed id, address indexed contractAddress, bytes data);

/// @dev The entry point of Polygon's FxChild that the chain's state sync calls.
interface IFxStateReceiver {
  function onStateReceive(uint256 stateId, bytes calldata data) external;
}

/// @dev The system address that Polygon's state sync calls FxChild from.
address constant POLYGON_STATE_SYNC_CALLER = 0x0000000000000000000000000000000000001001;

/// @dev The prerequisite script, pointed at the specified record.
contract DeployV4FeePolicyHarness is DeployV4FeePolicy {
  string internal recordName;

  constructor(string memory recordName_) {
    recordName = recordName_;
  }

  function _recordName() internal view override returns (string memory) {
    return recordName;
  }
}

/// @dev The proposal script, pointed at the specified record.
contract Proposal104Harness is Proposal104 {
  string internal recordName;

  constructor(string memory recordName_) {
    recordName = recordName_;
  }

  function _recordName() internal view override returns (string memory) {
    return recordName;
  }
}

/// @dev Tests for one chain's side of the proposal, against a fork of that chain. Each test runs
///      the prerequisite script on the fork. Each subcontract names the chain.
abstract contract Proposal104RemoteForkTest is V4FeeFixtureTest {
  Uniswap internal uniswap;
  Recorder internal recorder;

  uint256 internal remoteFork;
  uint256 internal mainnetFork;

  /// @dev The chain's EIP-155 chain id.
  function _chainId() internal pure virtual returns (uint256);

  function setUp() public {
    bool shouldRun = vm.envOr("SHOULD_FORK_TEST", false);
    vm.skip(!shouldRun);

    uint256 remoteBlock = _loadFixture(
      string.concat("test/end-to-end/proposal-104/fixtures/", vm.toString(_chainId()), ".json")
    );
    remoteFork = vm.createSelectFork(rpcAlias(_chainId()), remoteBlock);
    mainnetFork = vm.createFork("mainnet", MAINNET_BLOCK);
    uniswap.loadLatest();
  }

  /// @dev Asserts that each fixture pool's `before` is the fee the v1 adapter sets for it at the
  ///      fixture block.
  function test_feesBefore() public view {
    _assertFeesBefore();
  }

  /// @dev Runs the prerequisite script on the fork, then the chain's preflight.
  function test_preflightRemote() public {
    string memory recordName = _deploy("PreflightTest");

    new Proposal104Harness(recordName).preflightRemote();
  }

  /// @dev Runs the chain's action as the chain does, then asserts the adapter's new policy and
  ///      each fixture pool's fee.
  function test_execute() public {
    string memory recordName = _deploy("ExecuteTest");
    V4FeeAdapter adapter = V4FeeAdapter(v4FeeAdapter(_chainId()));
    _readStoredFeesBefore(adapter);

    _runAction();

    new Proposal104Harness(recordName).postflightRemote();
    _assertFees(adapter);
  }

  /// @inheritdoc V4FeeFixtureTest
  /// @dev The fee the chain's v1 adapter gives the pool.
  function _feeBefore(uint256 index) internal view override returns (uint24) {
    return V4FeeAdapter(v4FeeAdapter(_chainId())).getFee(_key(index));
  }

  /// @dev Runs the prerequisite script on the fork under a record name unique to this chain and
  ///      `test`, and points `recorder` at that record. Returns the record name. Leaves the
  ///      chain's fork selected.
  function _deploy(string memory test) internal returns (string memory recordName) {
    vm.selectFork(remoteFork);
    recordName = string.concat("Proposal104Remote", vm.toString(_chainId()), test);

    string memory recordPath = string.concat(".records/", recordName, ".json");
    if (vm.exists(recordPath)) vm.removeFile(recordPath);
    new DeployV4FeePolicyHarness(recordName).run();

    recorder.initialize({scriptName: recordName});
  }

  /// @dev Builds the proposal on the mainnet fork and runs this chain's action on the chain's
  ///      fork, after asserting the route delivers to this chain's governance executor. On Base
  ///      and OP Mainnet, replays the deposit transaction the action creates. On Polygon, replays
  ///      the state sync the action emits through FxChild. On BNB Chain and Arc, runs the call in
  ///      the payload the action publishes, as the receiver. On Ethereum, Arbitrum and Robinhood
  ///      Chain, runs the decoded call as the executor with the route's gas limit. Records
  ///      stand-in policies for the other chains, so `buildProposal` can read the record. Leaves
  ///      the chain's fork selected.
  function _runAction() internal {
    vm.selectFork(mainnetFork);
    uint256[8] memory list = chains();
    uint256 index;
    for (uint256 i; i < list.length; i++) {
      if (list[i] == _chainId()) index = i;
      else recorder.write(list[i], Records.V4_FEE_POLICY, address(uint160(0xB000 + i)));
    }
    Call memory action = buildProposal(uniswap, recorder).calls[index];
    address executor = v4Accounts(uniswap, _chainId()).governanceExecutor;

    if (_chainId() == ChainId.Base || _chainId() == ChainId.Optimism) {
      (address l1Messenger, address crossChainAccount,,) =
        L1CrossDomainMessengerDecoder.decode(action);
      checkOPStackMessengerEthereum(l1Messenger, _chainId(), "action");
      assertEq(crossChainAccount, executor, "l1CrossDomainMessenger.crossChainAccount");
      relayOPStackMessage(
        vm, uniswap.ethereum.timelock, action, l1Messenger, mainnetFork, remoteFork
      );
      return;
    }
    if (_chainId() == ChainId.Polygon) {
      _relayStateSync(action);
      return;
    }

    Call memory remoteCall;
    uint256 gasLimit = type(uint64).max;
    if (_chainId() == ChainId.Ethereum) {
      remoteCall = action;
    } else if (_chainId() == ChainId.Arbitrum || _chainId() == ChainId.Robinhood) {
      address inbox;
      address timelock;
      (inbox, timelock, gasLimit,,, remoteCall) = InboxDecoder.decode(action);
      checkInboxEthereum(inbox, _chainId(), "action");
      assertEq(InboxEncoder.arbitrumAlias(timelock), executor, "inbox.timelock");
    } else {
      remoteCall = _publishedWormholeCall(action, executor);
    }

    vm.selectFork(remoteFork);
    vm.prank(executor);
    (bool success, bytes memory returndata) =
      remoteCall.target.call{gas: gasLimit, value: remoteCall.value}(remoteCall.data);
    require(success, string(returndata));
  }

  /// @dev Executes `action` as the Timelock on the mainnet fork and returns its logs.
  function _executeAction(Call memory action) internal returns (Vm.Log[] memory) {
    vm.deal(uniswap.ethereum.timelock, action.value);
    vm.recordLogs();
    executeAsTimelock(vm, uniswap.ethereum.timelock, LibCall.newCalls([action]));
    return vm.getRecordedLogs();
  }

  /// @dev Executes `action` on the mainnet fork, then delivers the state sync it emits to
  ///      Polygon's FxChild on the chain's fork, as the chain's state sync does.
  function _relayStateSync(Call memory action) internal {
    Vm.Log[] memory logs = _executeAction(action);
    address stateSender = IFxRoot(uniswap.ethereum.bridge.polygon).stateSender();

    uint256 found;
    uint256 stateId;
    bytes memory data;
    for (uint256 i; i < logs.length; i++) {
      if (logs[i].emitter != stateSender || logs[i].topics[0] != StateSynced.selector) continue;
      assertEq(
        logs[i].topics[2], bytes32(uint256(uint160(POLYGON_FX_CHILD))), "StateSynced.fxChild"
      );
      stateId = uint256(logs[i].topics[1]);
      data = abi.decode(logs[i].data, (bytes));
      found++;
    }
    assertEq(found, 1, "StateSynced.count");

    vm.selectFork(remoteFork);
    vm.prank(POLYGON_STATE_SYNC_CALLER);
    IFxStateReceiver(POLYGON_FX_CHILD).onStateReceive(stateId, data);
  }

  /// @dev Executes `action` on the mainnet fork and returns the one call in the payload that
  ///      Uniswap's Wormhole sender publishes, after asserting the payload names `executor` and
  ///      this chain. The sender encodes the payload as a 32-byte header followed by the
  ///      `sendMessage` arguments.
  function _publishedWormholeCall(Call memory action, address executor)
    internal
    returns (Call memory)
  {
    Vm.Log[] memory logs = _executeAction(action);
    address core = uniswap.ethereum.bridge.wormholeCore;
    bytes32 sender = bytes32(uint256(uint160(uniswap.ethereum.bridge.bnbChain)));

    uint256 found;
    bytes memory payload;
    for (uint256 i; i < logs.length; i++) {
      if (logs[i].emitter != core) continue;
      if (logs[i].topics[0] != IWormholeCore.LogMessagePublished.selector) continue;
      assertEq(logs[i].topics[1], sender, "LogMessagePublished.sender");
      (,, payload,) = abi.decode(logs[i].data, (uint64, uint32, bytes, uint8));
      found++;
    }
    assertEq(found, 1, "LogMessagePublished.count");

    (
      ,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory datas,
      address receiver,
      uint16 wormholeChainId
    ) = abi.decode(payload, (bytes32, address[], uint256[], bytes[], address, uint16));
    assertEq(receiver, executor, "payload.receiver");
    assertEq(
      wormholeChainId,
      _chainId() == ChainId.BNBChain ? WormholeChainId.BNBChain : Arc.WORMHOLE_CHAIN_ID,
      "payload.chainId"
    );
    assertEq(targets.length, 1, "payload.targets.length");
    assertEq(values.length, 1, "payload.values.length");
    assertEq(datas.length, 1, "payload.datas.length");
    return Call({target: targets[0], value: values[0], data: datas[0]});
  }
}

contract Proposal104EthereumRemoteForkTest is Proposal104RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.Ethereum;
  }
}

contract Proposal104ArbitrumForkTest is Proposal104RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.Arbitrum;
  }
}

contract Proposal104BaseForkTest is Proposal104RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.Base;
  }
}

contract Proposal104OptimismForkTest is Proposal104RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.Optimism;
  }
}

contract Proposal104BNBChainForkTest is Proposal104RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.BNBChain;
  }
}

contract Proposal104PolygonForkTest is Proposal104RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.Polygon;
  }
}

contract Proposal104RobinhoodForkTest is Proposal104RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.Robinhood;
  }
}

contract Proposal104ArcForkTest is Proposal104RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return Arc.CHAIN_ID;
  }
}
