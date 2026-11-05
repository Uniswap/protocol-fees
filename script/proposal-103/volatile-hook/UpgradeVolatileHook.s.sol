// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";

import {Uniswap} from "govkit/types/Uniswap.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {ERC1967} from "govkit/constants/ERC1967.sol";
import {Call} from "govkit/types/Call.sol";
import {ERC1967Reader} from "govkit/forge/ERC1967Reader.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

import {VolatileHook, smokeCheck} from "./Constants.sol";
import {IVolatilePairHook} from "./Interfaces.sol";

// -------------------------------------------------------------------------------------------------
// NOTICE:
//
// This action is one Ethereum call: the Timelock, which holds the hook's `DEFAULT_ADMIN_ROLE`,
// upgrades the VolatilePairHook proxy to a new implementation.
//
// `../Proposal103.s.sol` runs `preflightEthereum()`. After the proposal executes, run the
// postflight to verify the outcome:
//
//    forge script script/proposal-103/volatile-hook/UpgradeVolatileHook.s.sol \
//      --sig "postflightEthereum()" --rpc-url mainnet
//

/// @dev Returns the call that upgrades the hook. A free function so the fork tests, and anything
///      outside this repo, build the same call the proposal carries without deploying a script.
function buildUpgradeVolatileHookCall() pure returns (Call memory) {
  smokeCheck();

  // Upgrade the hook's proxy to the new implementation. Requires the Timelock to hold the hook's
  // `DEFAULT_ADMIN_ROLE`.
  //
  // Parameters:
  //
  // - `target`: the hook's proxy.
  // - `newImplementation`: the new implementation.
  // - `data`: empty, since the new implementation adds no storage to initialize. Its only new
  // value, `maxTempFeeBlockGap`, is an immutable set at its deployment.
  //
  return Call({
    target: VolatileHook.PROXY,
    value: 0,
    data: abi.encodeCall(
      IVolatilePairHook.upgradeToAndCall, (VolatileHook.NEW_IMPLEMENTATION, bytes(""))
    )
  });
}

contract UpgradeVolatileHook is Script {
  Uniswap internal uniswap;

  constructor() {
    uniswap.loadLatest();
  }

  /// @dev `preflightEthereum()` at a specified block. Pin the fork to the same block so the
  ///      two cannot disagree:
  ///      `--sig "preflightEthereum(uint256)" $B --rpc-url mainnet --fork-block-number $B`.
  function preflightEthereum(uint256 blockNumber) public view {
    require(block.number == blockNumber, "block number");
    preflightEthereum();
  }

  /// @dev Asserts Ethereum is in the state the upgrade assumes: the proxy runs the current
  ///      implementation and answers to the Timelock, and the new implementation is deployed and
  ///      passes the checks the proxy's upgrade makes and the temporary fee parameter. Run against
  ///      Ethereum.
  function preflightEthereum() public view {
    smokeCheck();
    require(block.chainid == ChainId.Ethereum, "not Ethereum");
    console.log("preflight UpgradeVolatileHook at block", block.number);

    IVolatilePairHook proxy = IVolatilePairHook(VolatileHook.PROXY);
    IVolatilePairHook newImplementation = IVolatilePairHook(VolatileHook.NEW_IMPLEMENTATION);

    // Assert the proxy runs the implementation we expect to replace, and the Timelock can upgrade
    // it.
    require(
      ERC1967Reader.implementation(VolatileHook.PROXY) == VolatileHook.CURRENT_IMPLEMENTATION,
      "proxy.implementation"
    );
    require(
      proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), uniswap.ethereum.timelock), "proxy.timelockIsAdmin"
    );

    // Assert the new implementation is deployed and keeps the PoolManager, the hook permissions and
    // the UUPS slot.
    require(VolatileHook.NEW_IMPLEMENTATION.code.length != 0, "newImplementation.code");
    require(
      newImplementation.poolManager() == uniswap.ethereum.poolManager,
      "newImplementation.poolManager"
    );
    // Assert the permissions the new implementation declares match the flag bits in the proxy's
    // address; the same check the proxy's upgrade makes. Reverts with `HookAddressNotValid` on a
    // mismatch.
    Hooks.validateHookPermissions(
      IHooks(VolatileHook.PROXY), newImplementation.getHookPermissions()
    );
    require(
      newImplementation.proxiableUUID() == ERC1967.IMPLEMENTATION_SLOT,
      "newImplementation.proxiableUUID"
    );

    // Assert the new implementation has the expected temporary fee block gap.
    require(
      newImplementation.maxTempFeeBlockGap() == VolatileHook.MAX_TEMP_FEE_BLOCK_GAP,
      "newImplementation.maxTempFeeBlockGap"
    );
  }

  /// @dev Asserts the proxy runs the new implementation. The fork tests call this after executing
  ///      the upgrade; after the proposal executes, run it against Ethereum to verify the outcome.
  function postflightEthereum() public view {
    require(block.chainid == ChainId.Ethereum, "not Ethereum");
    console.log("postflight UpgradeVolatileHook at block", block.number);

    require(
      ERC1967Reader.implementation(VolatileHook.PROXY) == VolatileHook.NEW_IMPLEMENTATION,
      "proxy.implementation"
    );
    require(
      IVolatilePairHook(VolatileHook.PROXY).maxTempFeeBlockGap()
        == VolatileHook.MAX_TEMP_FEE_BLOCK_GAP,
      "proxy.maxTempFeeBlockGap"
    );
    console.log("hook upgraded to", VolatileHook.NEW_IMPLEMENTATION);
  }
}
