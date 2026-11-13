// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";

import {Uniswap} from "govkit/types/Uniswap.sol";
import {Call} from "govkit/types/Call.sol";
import {InboxEncoder} from "govkit/bridges/InboxEncoder.sol";
import {InboxDecoder} from "govkit/bridges/decoders/InboxDecoder.sol";

import {
  UpdateStableHookFeeConfig,
  buildUpdateStableHookFeeConfigCall
} from "../../../../script/proposal-103/stable-hook/UpdateStableHookFeeConfig.s.sol";

uint256 constant ARBITRUM_BLOCK = 523_900_000;

/// @dev Tests for the fee config update, against an Arbitrum fork.
contract UpdateStableHookFeeConfigForkTest is Test {
  Uniswap internal uniswap;

  function setUp() public {
    bool shouldRun = vm.envOr("SHOULD_FORK_TEST", false);
    vm.skip(!shouldRun);

    vm.createSelectFork("arbitrum", ARBITRUM_BLOCK);
    uniswap.loadLatest();
  }

  function test_preflightArbitrum() public {
    new UpdateStableHookFeeConfig().preflightArbitrum(ARBITRUM_BLOCK);
  }

  /// @dev Runs the proposal's retryable ticket as Arbitrum does, from the aliased Timelock within
  /// the ticket's gas limit, and asserts each pool's fee config carries the new `optimalFeeE6`.
  function test_runTicket() public {
    (,, uint256 gasLimit,,, Call memory remoteCall) =
      InboxDecoder.decode(buildUpdateStableHookFeeConfigCall(uniswap));

    vm.prank(InboxEncoder.arbitrumAlias(uniswap.ethereum.timelock));
    (bool success, bytes memory returndata) =
      remoteCall.target.call{gas: gasLimit, value: remoteCall.value}(remoteCall.data);
    require(success, string(returndata));

    new UpdateStableHookFeeConfig().postflightArbitrum();
  }
}
