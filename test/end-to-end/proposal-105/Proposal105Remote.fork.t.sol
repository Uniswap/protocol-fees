// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {Call} from "govkit/types/Call.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {
  L1CrossDomainMessengerDecoder
} from "govkit/bridges/decoders/L1CrossDomainMessengerDecoder.sol";

import {V4FeeAdapter} from "../../../src/feeAdapters/V4FeeAdapter.sol";
import {Proposal105, buildProposal} from "../../../script/proposal-105/Proposal105.s.sol";
import {DeployV4FeeAdapter} from "../../../script/proposal-105/prereq/DeployV4FeeAdapter.s.sol";
import {V4_FEE_ADAPTER_RECORD, chains} from "../../../script/proposal-105/params/Constants.sol";
import {v4Accounts} from "../../../script/proposal-104/params/Chains.sol";
import {V4FeeFixtureTest} from "../../utils/V4FeeFixtureTest.sol";
import {relayOPStackMessage} from "../../utils/OPStackDeposit.sol";

/// @dev Mainnet block the proposal is built at.
uint256 constant MAINNET_BLOCK = 26_450_800;

/// @dev The prerequisite script, pointed at the specified record.
contract DeployV4FeeAdapterHarness is DeployV4FeeAdapter {
  string internal recordName;

  constructor(string memory recordName_) {
    recordName = recordName_;
  }

  function _recordName() internal view override returns (string memory) {
    return recordName;
  }
}

/// @dev The proposal script, pointed at the specified record.
contract Proposal105Harness is Proposal105 {
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
abstract contract Proposal105RemoteForkTest is V4FeeFixtureTest {
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
      string.concat("test/end-to-end/proposal-105/fixtures/", vm.toString(_chainId()), ".json")
    );
    remoteFork = vm.createSelectFork(_rpcAlias(), remoteBlock);
    mainnetFork = vm.createFork("mainnet", MAINNET_BLOCK);
    uniswap.loadLatest();
  }

  /// @dev Runs the prerequisite script on the fork, then the chain's preflight.
  function test_preflightRemote() public {
    string memory recordName = _deploy("PreflightTest");

    new Proposal105Harness(recordName).preflightRemote();
  }

  /// @dev Replays the deposit transaction the chain's action creates, then asserts the
  ///      PoolManager's fee controller and each fixture pool's fee.
  function test_execute() public {
    string memory recordName = _deploy("ExecuteTest");

    _runAction();

    new Proposal105Harness(recordName).postflightRemote();
    _assertFees(V4FeeAdapter(recorder.read(_chainId(), V4_FEE_ADAPTER_RECORD)));
  }

  /// @dev Runs the prerequisite script on the fork under a record name unique to this chain and
  ///      `test`, and points `recorder` at that record. Returns the record name. Leaves the
  ///      chain's fork selected.
  function _deploy(string memory test) internal returns (string memory recordName) {
    vm.selectFork(remoteFork);
    recordName = string.concat("Proposal105Remote", vm.toString(_chainId()), test);

    string memory recordPath = string.concat(".records/", recordName, ".json");
    if (vm.exists(recordPath)) vm.removeFile(recordPath);
    new DeployV4FeeAdapterHarness(recordName).run();

    recorder.initialize({scriptName: recordName});
  }

  /// @dev Builds the proposal on the mainnet fork, asserts this chain's message goes to its
  ///      CrossChainAccount, and replays the deposit transaction the message creates on the chain's
  ///      fork. Records stand-in adapters for the other chains, so `buildProposal` can read the
  ///      record. Leaves the chain's fork selected.
  function _runAction() internal {
    vm.selectFork(mainnetFork);
    uint256[5] memory list = chains();
    uint256 index;
    for (uint256 i; i < list.length; i++) {
      if (list[i] == _chainId()) index = i;
      else recorder.write(list[i], V4_FEE_ADAPTER_RECORD, address(uint160(0xC000 + i)));
    }
    Call memory action = buildProposal(uniswap, recorder).calls[index];

    (address l1Messenger, address crossChainAccount,,) =
      L1CrossDomainMessengerDecoder.decode(action);
    assertEq(
      crossChainAccount,
      v4Accounts(uniswap, _chainId()).governanceExecutor,
      "l1CrossDomainMessenger.crossChainAccount"
    );
    relayOPStackMessage(vm, uniswap.ethereum.timelock, action, l1Messenger, mainnetFork, remoteFork);
  }
}

contract Proposal105CeloForkTest is Proposal105RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.Celo;
  }

  function _rpcAlias() internal pure override returns (string memory) {
    return "celo";
  }
}

contract Proposal105SoneiumForkTest is Proposal105RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.Soneium;
  }

  function _rpcAlias() internal pure override returns (string memory) {
    return "soneium";
  }
}

contract Proposal105XLayerForkTest is Proposal105RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.XLayer;
  }

  function _rpcAlias() internal pure override returns (string memory) {
    return "xlayer";
  }
}

contract Proposal105WorldChainForkTest is Proposal105RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.WorldChain;
  }

  function _rpcAlias() internal pure override returns (string memory) {
    return "world_chain";
  }
}

contract Proposal105ZoraForkTest is Proposal105RemoteForkTest {
  function _chainId() internal pure override returns (uint256) {
    return ChainId.Zora;
  }

  function _rpcAlias() internal pure override returns (string memory) {
    return "zora";
  }
}
