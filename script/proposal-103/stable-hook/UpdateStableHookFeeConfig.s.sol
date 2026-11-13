// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";

import {Uniswap} from "govkit/types/Uniswap.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {Call} from "govkit/types/Call.sol";
import {InboxEncoder} from "govkit/bridges/InboxEncoder.sol";
import {IInbox} from "govkit/interfaces/bridges/IInbox.sol";
import {IArbSys} from "briefcase/protocols/uniswapx/interfaces/IArbSys.sol";

import {StableHook, StablePool} from "./Constants.sol";
import {IStablePairHook, StableFeeConfig, IArbitrumBridge, IArbitrumRollup} from "./Interfaces.sol";

// -------------------------------------------------------------------------------------------------
// NOTICE:
//
// This action is one Ethereum call: the Timelock sends a retryable ticket through Arbitrum's Inbox,
// and Arbitrum runs the ticket from the aliased Timelock, which holds the hook's
// `CONFIG_MANAGER_ROLE`. The ticket sets each pool's `optimalFeeE6` and keeps its other fee config
// fields unchanged.
//
// `../Proposal103.s.sol` runs `preflightEthereum()`. Before proposing, run the preflight against
// Arbitrum:
//
//    forge script script/proposal-103/stable-hook/UpdateStableHookFeeConfig.s.sol \
//      --sig "preflightArbitrum()" --rpc-url arbitrum
//
// After the ticket runs on Arbitrum, run the postflight to verify the outcome:
//
//    forge script script/proposal-103/stable-hook/UpdateStableHookFeeConfig.s.sol \
//      --sig "postflightArbitrum()" --rpc-url arbitrum
//

/// @dev Arbitrum's ArbSys precompile.
IArbSys constant ARB_SYS = IArbSys(address(0x64));

/// @dev Returns the call that updates the pools' fee configs. A free function so the fork tests,
/// and anything outside this repo, build the same call the proposal carries without deploying a
///      script.
function buildUpdateStableHookFeeConfigCall(Uniswap storage uniswap) view returns (Call memory) {
  StablePool[] memory pools = StableHook.pools();
  bytes32[] memory poolIds = new bytes32[](pools.length);
  StableFeeConfig[] memory feeConfigs = new StableFeeConfig[](pools.length);
  for (uint256 i; i < pools.length; i++) {
    poolIds[i] = pools[i].id;
    feeConfigs[i] = StableHook.feeConfig(StableHook.NEW_OPTIMAL_FEE_E6);
  }

  // Send a retryable ticket that updates every pool's fee config in one call, with govkit's default
  // gas limit and fees. Requires the aliased Timelock to hold the hook's `CONFIG_MANAGER_ROLE`.
  //
  // Parameters:
  //
  // - `target`: the hook's proxy.
  // - `poolIds`: the pools to update.
  // - `feeConfigs`: each pool's fee config with the new `optimalFeeE6`, index-aligned with
  // `poolIds`. The hook replaces the whole struct, so the other three fields carry their current
  // values.
  //
  return InboxEncoder.encode({
    inbox: uniswap.ethereum.bridge.arbitrum,
    timelock: uniswap.ethereum.timelock,
    remoteCall: Call({
      target: StableHook.PROXY,
      value: 0,
      data: abi.encodeCall(IStablePairHook.batchUpdateFeeConfig, (poolIds, feeConfigs))
    })
  });
}

contract UpdateStableHookFeeConfig is Script {
  Uniswap internal uniswap;

  constructor() {
    uniswap.loadLatest();
  }

  /// @dev `preflightEthereum()` at a specified block. Pin the fork to the same block so the two
  ///      cannot disagree:
  ///      `--sig "preflightEthereum(uint256)" $B --rpc-url mainnet --fork-block-number $B`.
  function preflightEthereum(uint256 blockNumber) public view {
    require(block.number == blockNumber, "block number");
    preflightEthereum();
  }

  /// @dev Asserts Ethereum is in the state the update assumes: Arbitrum's Inbox delivers to
  ///      Arbitrum One and is not paused. Run against Ethereum.
  function preflightEthereum() public view {
    require(block.chainid == ChainId.Ethereum, "not Ethereum");
    console.log("preflightEthereum UpdateStableHookFeeConfig at block", block.number);

    IInbox inbox = IInbox(uniswap.ethereum.bridge.arbitrum);

    // Assert the Inbox's bridge delivers to the rollup that runs Arbitrum One.
    require(
      IArbitrumRollup(IArbitrumBridge(inbox.bridge()).rollup()).chainId() == ChainId.Arbitrum,
      "inbox.rollup.chainId"
    );
    require(!inbox.paused(), "inbox.paused");
  }

  /// @dev `preflightArbitrum()` at a specified block. Pin the fork to the same block so the two
  ///      cannot disagree:
  ///      `--sig "preflightArbitrum(uint256)" $B --rpc-url arbitrum --fork-block-number $B`.
  function preflightArbitrum(uint256 blockNumber) public view {
    // On Arbitrum `block.number` returns an Ethereum block number, so compare Arbitrum's blocks.
    require(ARB_SYS.arbBlockNumber() == blockNumber, "block number");
    preflightArbitrum();
  }

  /// @dev Asserts Arbitrum is in the state the update assumes: the aliased Timelock can update the
  ///      pools' fee configs, and each config holds the values the update keeps. Run against
  ///      Arbitrum.
  function preflightArbitrum() public view {
    require(block.chainid == ChainId.Arbitrum, "not Arbitrum");
    console.log("preflightArbitrum UpdateStableHookFeeConfig at block", ARB_SYS.arbBlockNumber());

    IStablePairHook hook = IStablePairHook(StableHook.PROXY);

    // Assert the aliased Timelock, which runs the retryable ticket, can update the fee configs.
    require(
      hook.hasRole(
        hook.CONFIG_MANAGER_ROLE(), InboxEncoder.arbitrumAlias(uniswap.ethereum.timelock)
      ),
      "hook.aliasedTimelockIsConfigManager"
    );

    // Assert each pool's fee config is the one the update replaces, so the update changes only
    // `optimalFeeE6`.
    StablePool[] memory pools = StableHook.pools();
    for (uint256 i; i < pools.length; i++) {
      _assertFeeConfig(pools[i].id, StableHook.feeConfig(pools[i].currentOptimalFeeE6));
    }
  }

  /// @dev Asserts each pool's fee config carries the new `optimalFeeE6`. The fork tests call this
  ///      after running the ticket; after it runs on Arbitrum, run it against Arbitrum to verify
  ///      the outcome.
  function postflightArbitrum() public view {
    require(block.chainid == ChainId.Arbitrum, "not Arbitrum");
    console.log("postflightArbitrum UpdateStableHookFeeConfig at block", ARB_SYS.arbBlockNumber());

    StablePool[] memory pools = StableHook.pools();
    for (uint256 i; i < pools.length; i++) {
      _assertFeeConfig(pools[i].id, StableHook.feeConfig(StableHook.NEW_OPTIMAL_FEE_E6));
    }
    console.log("optimalFeeE6 set to", StableHook.NEW_OPTIMAL_FEE_E6);
  }

  /// @dev Asserts the fee config of the pool `poolId` equals `expected`.
  function _assertFeeConfig(bytes32 poolId, StableFeeConfig memory expected) internal view {
    (uint24 k, uint24 optimalFeeE6, uint8 targetMultiplier, uint160 referenceSqrtPriceX96) =
      IStablePairHook(StableHook.PROXY).feeConfig(poolId);

    require(k == expected.k, "feeConfig.k");
    require(optimalFeeE6 == expected.optimalFeeE6, "feeConfig.optimalFeeE6");
    require(targetMultiplier == expected.targetMultiplier, "feeConfig.targetMultiplier");
    require(
      referenceSqrtPriceX96 == expected.referenceSqrtPriceX96, "feeConfig.referenceSqrtPriceX96"
    );
  }
}
