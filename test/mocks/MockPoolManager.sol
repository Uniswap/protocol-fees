// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {ProtocolFees} from "v4-core/ProtocolFees.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Pool} from "v4-core/libraries/Pool.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Slot0} from "v4-core/types/Slot0.sol";
import {Pool} from "v4-core/libraries/Pool.sol";

contract MockPoolManager is ProtocolFees {
  error NotSupported();

  uint160 constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

  constructor(address initialOwner) ProtocolFees(initialOwner) {}

  mapping(PoolId => Pool.State) mockPoolStates;

  /// @dev abstract internal function to allow the ProtocolFees contract to access the lock
  function _isUnlocked() internal pure override returns (bool) {
    return false;
  }

  function mockInitialize(PoolKey memory poolKey) external {
    Pool.State storage state = mockPoolStates[poolKey.toId()];
    // set a price on the pool so that it is "initialized"
    state.slot0 = Slot0.wrap(bytes32(0)).setSqrtPriceX96(SQRT_PRICE_1_1);
  }

  /// @dev abstract internal function to allow the ProtocolFees contract to access pool state
  /// @dev this is overridden in PoolManager.sol to give access to the _pools mapping
  function _getPool(PoolId id) internal view override returns (Pool.State storage) {
    return mockPoolStates[id];
  }

  function getProtocolFee(PoolId id) external view returns (uint24) {
    return mockPoolStates[id].slot0.protocolFee();
  }

  function setProtocolFeesAccrued(Currency currency, uint256 amount) external {
    protocolFeesAccrued[currency] = amount;
  }
}
