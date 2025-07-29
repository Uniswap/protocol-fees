// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {ProtocolFees} from "v4-core/ProtocolFees.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Pool} from "v4-core/libraries/Pool.sol";

contract MockPoolManager is ProtocolFees {
  error NotSupported();

  constructor(address initialOwner) ProtocolFees(initialOwner) {}

  /// @dev abstract internal function to allow the ProtocolFees contract to access the lock
  function _isUnlocked() internal pure override returns (bool) {
    return false;
  }

  /// @dev abstract internal function to allow the ProtocolFees contract to access pool state
  /// @dev this is overridden in PoolManager.sol to give access to the _pools mapping
  function _getPool(PoolId) internal pure override returns (Pool.State storage) {
    revert NotSupported();
  }

  function setProtocolFeesAccrued(Currency currency, uint256 amount) external {
    protocolFeesAccrued[currency] = amount;
  }
}
