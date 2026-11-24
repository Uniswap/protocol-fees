// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {V4FeeAdapter} from "../../../src/feeAdapters/V4FeeAdapter.sol";

import {DeployV4FeePolicy} from "../../proposal-104/prereq/DeployV4FeePolicy.s.sol";
import {v4Accounts} from "../../proposal-104/params/Chains.sol";
import {readRecord} from "../../proposal-104/params/Constants.sol";
import {
  RECORD_NAME,
  POLICY_PARAMS_JSON,
  V4_FEE_ADAPTER_RECORD,
  tokenJar
} from "../params/Constants.sol";
import {checkNewAdapter} from "../AdapterCheck.sol";

/// @title DeployV4FeeAdapter
/// @notice Deploys what proposal 104's `DeployV4FeePolicy` deploys, plus a `V4FeeAdapter` that
///         uses the new policy, hands both to the chain's CrossChainAccount, and records the
///         addresses in `.records/Proposal105.json`, where the proposal reads them. Anyone can run
///         it; the deployer holds no authority once it finishes.
/// @dev Run it once on each of the five proposal 105 chains:
///
///      forge script script/proposal-105/prereq/DeployV4FeeAdapter.s.sol --rpc-url <chain> \
///        --broadcast
///
///      To assert the recorded deployment against the live chain afterwards:
///
///      forge script script/proposal-105/prereq/DeployV4FeeAdapter.s.sol --sig "check()" \
///        --rpc-url <chain>
contract DeployV4FeeAdapter is DeployV4FeePolicy {
  V4FeeAdapter internal adapter;

  /// @inheritdoc DeployV4FeePolicy
  function _deploy() internal override {
    super._deploy();

    // ---------------------------------------------------------------------------------------------
    // Transaction after the policy handoff
    //
    // Deploy the adapter. The deployer is its owner until the handoff below.
    //
    adapter = new V4FeeAdapter({
      poolManager: IPoolManager(v4Accounts(uniswap, block.chainid).poolManager),
      tokenJar: tokenJar(uniswap, block.chainid)
    });

    // ---------------------------------------------------------------------------------------------
    // Last three transactions
    //
    // Set the adapter's policy, then hand the adapter to the governance executor. Set the fee
    // setter before the owner, because only the owner can set it.
    //
    adapter.setPolicy(deployment.policy);
    adapter.setFeeSetter(governanceExecutor);
    adapter.transferOwnership(governanceExecutor);
  }

  /// @inheritdoc DeployV4FeePolicy
  function _check() internal override {
    super._check();
    checkNewAdapter(
      adapter,
      v4Accounts(uniswap, block.chainid).poolManager,
      tokenJar(uniswap, block.chainid),
      address(deployment.policy),
      governanceExecutor
    );
  }

  /// @inheritdoc DeployV4FeePolicy
  function _record() internal override {
    super._record();
    _write(V4_FEE_ADAPTER_RECORD, address(adapter));
  }

  /// @inheritdoc DeployV4FeePolicy
  function _read() internal override {
    super._read();
    adapter = V4FeeAdapter(readRecord(recorder, block.chainid, V4_FEE_ADAPTER_RECORD));
  }

  /// @inheritdoc DeployV4FeePolicy
  function _recordName() internal view virtual override returns (string memory) {
    return RECORD_NAME;
  }

  /// @inheritdoc DeployV4FeePolicy
  function _paramsPath() internal view virtual override returns (string memory) {
    return POLICY_PARAMS_JSON;
  }
}
