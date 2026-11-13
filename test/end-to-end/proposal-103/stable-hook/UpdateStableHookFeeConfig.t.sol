// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";

import {Uniswap} from "govkit/types/Uniswap.sol";
import {Call} from "govkit/types/Call.sol";
import {InboxDecoder} from "govkit/bridges/decoders/InboxDecoder.sol";

import {
  buildUpdateStableHookFeeConfigCall
} from "../../../../script/proposal-103/stable-hook/UpdateStableHookFeeConfig.s.sol";
import {StableHook} from "../../../../script/proposal-103/stable-hook/Constants.sol";
import {
  IStablePairHook,
  StableFeeConfig
} from "../../../../script/proposal-103/stable-hook/Interfaces.sol";

/// @dev Unit tests for the update's encoding.
contract UpdateStableHookFeeConfigTest is Test {
  Uniswap internal uniswap;

  function setUp() public {
    uniswap.loadLatest();
  }

  /// @dev Asserts the action is one retryable ticket from the Timelock through Arbitrum's Inbox,
  /// with govkit's default gas limit and fees and the ETH to pay them, whose call on Arbitrum is
  /// exactly `batchUpdateFeeConfig` to the hook, setting each pool's `optimalFeeE6` to
  /// `NEW_OPTIMAL_FEE_E6`, with no value.
  function test_buildUpdateStableHookFeeConfigCall() public view {
    Call memory call = buildUpdateStableHookFeeConfigCall(uniswap);

    (
      address inbox,
      address timelock,
      uint256 gasLimit,
      uint256 maxFeePerGas,
      uint256 maxSubmissionCost,
      Call memory remoteCall
    ) = InboxDecoder.decode(call);

    // Assert the envelope: Arbitrum's Inbox, the Timelock, the default gas limit and fees, and the
    // ETH that pays them.
    assertEq(inbox, uniswap.ethereum.bridge.arbitrum, "inbox");
    assertEq(timelock, uniswap.ethereum.timelock, "timelock");
    assertEq(gasLimit, 200_000, "gasLimit");
    assertEq(maxFeePerGas, 0.1 gwei, "maxFeePerGas");
    assertEq(maxSubmissionCost, 0.01 ether, "maxSubmissionCost");
    assertEq(call.value, gasLimit * maxFeePerGas + maxSubmissionCost, "call.value");

    // Assert the remote call sets each pool's `optimalFeeE6` to `NEW_OPTIMAL_FEE_E6`.
    assertEq(remoteCall.target, StableHook.PROXY, "remoteCall.target");
    assertEq(remoteCall.value, 0, "remoteCall.value");
    bytes32[] memory poolIds = new bytes32[](2);
    poolIds[0] = StableHook.TICK_SPACING_1_POOL_ID;
    poolIds[1] = StableHook.TICK_SPACING_2_POOL_ID;
    StableFeeConfig[] memory feeConfigs = new StableFeeConfig[](2);
    feeConfigs[0] = StableHook.feeConfig(StableHook.NEW_OPTIMAL_FEE_E6);
    feeConfigs[1] = StableHook.feeConfig(StableHook.NEW_OPTIMAL_FEE_E6);
    assertEq(
      remoteCall.data,
      abi.encodeWithSelector(IStablePairHook.batchUpdateFeeConfig.selector, poolIds, feeConfigs),
      "remoteCall.data"
    );
  }
}
