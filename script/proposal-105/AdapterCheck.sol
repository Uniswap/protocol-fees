// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {V4FeeAdapter} from "../../src/feeAdapters/V4FeeAdapter.sol";
import {IV3OpenFeeAdapter} from "../../src/interfaces/IV3OpenFeeAdapter.sol";

/// @notice Asserts that `adapter` is a `V4FeeAdapter` for `poolManager` and `tokenJar`, that
///         `tokenJar` is also the TokenJar of the chain's `v3OpenFeeAdapter`, that `adapter` uses
///         `policy`, and that `governanceExecutor` owns it and sets its pool overrides.
/// @dev The prerequisite script runs it on its own deployment, and the preflight runs it on the
///      recorded deployment. It reads getters and does not compare code.
function checkNewAdapter(
  V4FeeAdapter adapter,
  address poolManager,
  address tokenJar,
  address v3OpenFeeAdapter,
  address policy,
  address governanceExecutor
) view {
  require(address(adapter).code.length != 0, "adapter.code");
  require(address(adapter.POOL_MANAGER()) == poolManager, "adapter.POOL_MANAGER");
  require(adapter.TOKEN_JAR() == tokenJar, "adapter.TOKEN_JAR");
  require(IV3OpenFeeAdapter(v3OpenFeeAdapter).TOKEN_JAR() == tokenJar, "v3OpenFeeAdapter.TOKEN_JAR");
  require(address(adapter.policy()) == policy, "adapter.policy");
  require(adapter.owner() == governanceExecutor, "adapter.owner");
  require(adapter.feeSetter() == governanceExecutor, "adapter.feeSetter");
}
