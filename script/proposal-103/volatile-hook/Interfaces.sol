// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Hooks} from "v4-core/libraries/Hooks.sol";

/// @dev The parts of `VolatilePairHook` this proposal reads and calls. The hook lives in
/// `Uniswap/v4-hooks-public`, which this repository does not depend on.
interface IVolatilePairHook {
  function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
  function proxiableUUID() external view returns (bytes32);
  function poolManager() external view returns (address);
  function getHookPermissions() external pure returns (Hooks.Permissions memory);
  function maxTempFeeBlockGap() external view returns (uint256);
  function hasRole(bytes32 role, address account) external view returns (bool);
  function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
}
