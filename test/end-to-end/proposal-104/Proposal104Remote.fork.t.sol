// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {Call} from "govkit/types/Call.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {InboxDecoder} from "govkit/bridges/decoders/InboxDecoder.sol";
import {
  L1CrossDomainMessengerDecoder
} from "govkit/bridges/decoders/L1CrossDomainMessengerDecoder.sol";
import {WormholeDecoder} from "govkit/bridges/decoders/WormholeDecoder.sol";
import {FxRootDecoder} from "govkit/bridges/decoders/FxRootDecoder.sol";
import {InboxEncoder} from "govkit/bridges/InboxEncoder.sol";

import {V4FeeAdapter} from "../../../src/feeAdapters/V4FeeAdapter.sol";
import {Proposal104, buildProposal} from "../../../script/proposal-104/Proposal104.s.sol";
import {DeployV4FeePolicy} from "../../../script/proposal-104/prereq/DeployV4FeePolicy.s.sol";
import {Records, v4FeeAdapter} from "../../../script/proposal-104/params/Constants.sol";
import {v4Accounts} from "../../../script/proposal-104/params/Chains.sol";
import {Arc} from "../../../script/proposal-7/params/Constants.sol";
import {WormholeDecode} from "../../utils/WormholeDecode.sol";
import {relayOPStackMessage} from "../../utils/OPStackDeposit.sol";
import {V4FeeFixtureTest} from "../../utils/V4FeeFixtureTest.sol";

/// @dev Mainnet block the proposal is built at. `buildProposal` reads the Wormhole message fee
///      from the mainnet core.
uint256 constant MAINNET_BLOCK = 26_450_800;

/// @dev The eight chains in the order of the proposal's actions.
function proposalChains() pure returns (uint256[8] memory) {
  return [
    ChainId.Ethereum,
    ChainId.Arbitrum,
    ChainId.Base,
    ChainId.Optimism,
    ChainId.BNBChain,
    ChainId.Polygon,
    ChainId.Robinhood,
    Arc.CHAIN_ID
  ];
}

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

  /// @dev The chain's RPC alias in `foundry.toml`.
  function _rpcAlias() internal pure virtual returns (string memory);

  function setUp() public {
    bool shouldRun = vm.envOr("SHOULD_FORK_TEST", false);
    vm.skip(!shouldRun);

    uint256 remoteBlock = _loadFixture(
      string.concat("test/end-to-end/proposal-104/fixtures/", vm.toString(_chainId()), ".json")
    );
    remoteFork = vm.createSelectFork(_rpcAlias(), remoteBlock);
    mainnetFork = vm.createFork("mainnet", MAINNET_BLOCK);
    uniswap.loadLatest();
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
    _readFeesBefore(adapter);

    _runAction();

    new Proposal104Harness(recordName).postflightRemote();
    _assertFees(adapter);
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
  ///      fork. On Base and OP Mainnet, replays the deposit transaction the action creates. On the
  ///      other chains, runs the decoded call as the governance executor with the gas limit of the
  ///      route, after asserting the route delivers to the executor. Records stand-in policies for
  ///      the other chains, so `buildProposal` can read the record. Leaves the chain's fork
  ///      selected.
  function _runAction() internal {
    vm.selectFork(mainnetFork);
    uint256[8] memory chains = proposalChains();
    uint256 index;
    for (uint256 i; i < chains.length; i++) {
      if (chains[i] == _chainId()) index = i;
      else recorder.write(chains[i], Records.V4_FEE_POLICY, address(uint160(0xB000 + i)));
    }
    Call memory action = buildProposal(uniswap, recorder).calls[index];
    address executor = v4Accounts(uniswap, _chainId()).governanceExecutor;

    if (_chainId() == ChainId.Base || _chainId() == ChainId.Optimism) {
      (address l1Messenger, address crossChainAccount,,) =
        L1CrossDomainMessengerDecoder.decode(action);
      assertEq(crossChainAccount, executor, "l1CrossDomainMessenger.crossChainAccount");
      relayOPStackMessage(
        vm, uniswap.ethereum.timelock, action, l1Messenger, mainnetFork, remoteFork
      );
      return;
    }

    Call memory remoteCall;
    uint256 gasLimit = type(uint64).max;
    if (_chainId() == ChainId.Ethereum) {
      remoteCall = action;
    } else if (_chainId() == ChainId.Arbitrum || _chainId() == ChainId.Robinhood) {
      address timelock;
      (, timelock, gasLimit,,, remoteCall) = InboxDecoder.decode(action);
      assertEq(InboxEncoder.arbitrumAlias(timelock), executor, "inbox.timelock");
    } else if (_chainId() == ChainId.BNBChain) {
      (address receiver, uint256 chainId, Call[] memory calls) = _wormhole(action);
      assertEq(receiver, executor, "wormhole.receiver");
      assertEq(chainId, ChainId.BNBChain, "wormhole.chainId");
      remoteCall = _only(calls);
    } else if (_chainId() == ChainId.Polygon) {
      (, address fxReceiver, Call[] memory calls) = FxRootDecoder.decode(action);
      assertEq(fxReceiver, executor, "fxRoot.fxReceiver");
      remoteCall = _only(calls);
    } else {
      (, address receiver, uint16 wormholeChainId,, Call[] memory calls) =
        WormholeDecode.decode(action);
      assertEq(receiver, executor, "wormhole.receiver");
      assertEq(wormholeChainId, Arc.WORMHOLE_CHAIN_ID, "wormhole.chainId");
      remoteCall = _only(calls);
    }

    vm.selectFork(remoteFork);
    vm.prank(executor);
    (bool success, bytes memory returndata) =
      remoteCall.target.call{gas: gasLimit, value: remoteCall.value}(remoteCall.data);
    require(success, string(returndata));
  }

  /// @dev Returns the receiver, chain id and calls of a govkit Wormhole action.
  function _wormhole(Call memory action)
    internal
    pure
    returns (address receiver, uint256 chainId, Call[] memory calls)
  {
    (, receiver, chainId,, calls) = WormholeDecoder.decode(action);
  }

  /// @dev Asserts `calls` has one call, and returns it.
  function _only(Call[] memory calls) internal pure returns (Call memory) {
    assertEq(calls.length, 1, "remoteCalls.length");
    return calls[0];
  }
}

contract Proposal104EthereumRemoteForkTest is Proposal104RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.Ethereum;
  }

  function _rpcAlias() internal pure override returns (string memory) {
    return "mainnet";
  }
}

contract Proposal104ArbitrumForkTest is Proposal104RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.Arbitrum;
  }

  function _rpcAlias() internal pure override returns (string memory) {
    return "arbitrum";
  }
}

contract Proposal104BaseForkTest is Proposal104RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.Base;
  }

  function _rpcAlias() internal pure override returns (string memory) {
    return "base";
  }
}

contract Proposal104OptimismForkTest is Proposal104RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.Optimism;
  }

  function _rpcAlias() internal pure override returns (string memory) {
    return "optimism";
  }
}

contract Proposal104BNBChainForkTest is Proposal104RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.BNBChain;
  }

  function _rpcAlias() internal pure override returns (string memory) {
    return "bnb_chain";
  }
}

contract Proposal104PolygonForkTest is Proposal104RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.Polygon;
  }

  function _rpcAlias() internal pure override returns (string memory) {
    return "polygon";
  }
}

contract Proposal104RobinhoodForkTest is Proposal104RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.Robinhood;
  }

  function _rpcAlias() internal pure override returns (string memory) {
    return "robinhood";
  }
}

contract Proposal104ArcForkTest is Proposal104RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return Arc.CHAIN_ID;
  }

  function _rpcAlias() internal pure override returns (string memory) {
    return "arc";
  }
}
