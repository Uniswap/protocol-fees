// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {V4FeeAdapter} from "../../src/feeAdapters/V4FeeAdapter.sol";

/// @notice Asserts that `adapter` is a `V4FeeAdapter` for `poolManager` and `tokenJar`, that it
///         uses `policy`, and that `governanceExecutor` owns it and sets its pool overrides.
/// @dev The prerequisite script runs it on its own deployment, and the preflight runs it on the
///      recorded deployment. It reads getters and does not compare code.
function checkNewAdapter(
  V4FeeAdapter adapter,
  address poolManager,
  address tokenJar,
  address policy,
  address governanceExecutor
) view {
  require(address(adapter).code.length != 0, "adapter.code");
  require(address(adapter.POOL_MANAGER()) == poolManager, "adapter.POOL_MANAGER");
  require(adapter.TOKEN_JAR() == tokenJar, "adapter.TOKEN_JAR");
  require(address(adapter.policy()) == policy, "adapter.policy");
  require(adapter.owner() == governanceExecutor, "adapter.owner");
  require(adapter.feeSetter() == governanceExecutor, "adapter.feeSetter");
}
