// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";

import {Uniswap} from "govkit/types/Uniswap.sol";
import {LibCall} from "govkit/types/Call.sol";

import {
  UpgradeVolatileHook,
  buildUpgradeVolatileHookCall
} from "../../../../script/proposal-103/volatile-hook/UpgradeVolatileHook.s.sol";
import {VolatileHook} from "../../../../script/proposal-103/volatile-hook/Constants.sol";
import {IVolatilePairHook} from "../../../../script/proposal-103/volatile-hook/Interfaces.sol";
import {executeAsTimelock} from "../../../utils/TimelockExecution.sol";

/// @dev After the new implementation's deployment at block 26_347_359.
uint256 constant MAINNET_BLOCK = 26_349_000;

/// @dev Tests for the hook upgrade, against a mainnet fork.
contract UpgradeVolatileHookForkTest is Test {
  Uniswap internal uniswap;

  function setUp() public {
    bool shouldRun = vm.envOr("SHOULD_FORK_TEST", false);
    vm.skip(!shouldRun);

    vm.createSelectFork("mainnet", MAINNET_BLOCK);
    uniswap.loadLatest();
  }

  function test_preflightEthereum() public {
    new UpgradeVolatileHook().preflightEthereum(block.number);
  }

  /// @dev Executes the upgrade as the Timelock and asserts the proxy runs the new implementation
  /// and the Timelock keeps its admin role.
  function test_upgrade() public {
    IVolatilePairHook proxy = IVolatilePairHook(VolatileHook.PROXY);

    executeAsTimelock(
      vm, uniswap.ethereum.timelock, LibCall.newCalls([buildUpgradeVolatileHookCall()])
    );

    new UpgradeVolatileHook().postflightEthereum();
    assertTrue(
      proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), uniswap.ethereum.timelock), "timelockIsAdmin"
    );
  }
}
