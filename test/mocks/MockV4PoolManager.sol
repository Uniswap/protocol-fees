// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {ProtocolFees} from "v4-core/ProtocolFees.sol";
import {Extsload} from "v4-core/Extsload.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Pool} from "v4-core/libraries/Pool.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Slot0} from "v4-core/types/Slot0.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IExtsload} from "v4-core/interfaces/IExtsload.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";

/// @title MockV4PoolManager
/// @notice A minimal mock of the V4 PoolManager that supports ProtocolFees, extsload, and
/// enough IPoolManager surface for the V4FeeAdapter to function. Pools are stored in a
/// mapping at the same storage slot as the real PoolManager (slot 6 via POOLS_SLOT) because
/// ProtocolFees uses the same internal _getPool pattern.
/// @dev This mock does NOT implement the full IPoolManager interface. Unimplemented functions
/// revert with NotSupported().
contract MockV4PoolManager is ProtocolFees, Extsload {
  using PoolIdLibrary for PoolKey;

  error NotSupported();

  uint160 constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

  /// @dev The pools mapping. In the real PoolManager, this is at storage slot 6
  /// (StateLibrary.POOLS_SLOT). Our storage layout must match for extsload to work:
  /// Owned.owner (slot 0), ProtocolFees.protocolFeesAccrued (slot 1),
  /// ProtocolFees.protocolFeeController (slot 2), and then we need 3 padding slots
  /// before _pools lands at slot 6. We use explicit padding variables.
  uint256 private _pad3;
  uint256 private _pad4;
  uint256 private _pad5;
  mapping(PoolId => Pool.State) internal _pools;

  constructor(address initialOwner) ProtocolFees(initialOwner) {}

  /// @notice Initialize a pool with the standard 1:1 price.
  /// @param poolKey The pool key to initialize.
  function mockInitialize(PoolKey memory poolKey) external {
    Pool.State storage state = _pools[poolKey.toId()];
    state.slot0 = Slot0.wrap(bytes32(0)).setSqrtPriceX96(SQRT_PRICE_1_1);
  }

  /// @notice Initialize a pool with a specific LP fee set in Slot0.
  /// @param poolKey The pool key to initialize.
  /// @param lpFee The LP fee to set.
  function mockInitializeWithLpFee(PoolKey memory poolKey, uint24 lpFee) external {
    Pool.State storage state = _pools[poolKey.toId()];
    state.slot0 = Slot0.wrap(bytes32(0)).setSqrtPriceX96(SQRT_PRICE_1_1).setLpFee(lpFee);
  }

  /// @notice Read the protocol fee from a pool's Slot0.
  /// @param id The pool ID to query.
  /// @return The protocol fee currently set on the pool.
  function getProtocolFee(PoolId id) external view returns (uint24) {
    return _pools[id].slot0.protocolFee();
  }

  /// @notice Set accrued protocol fees for a currency (for testing collection).
  /// @param currency The currency to set fees for.
  /// @param amount The amount of fees accrued.
  function setProtocolFeesAccrued(Currency currency, uint256 amount) external {
    protocolFeesAccrued[currency] = amount;
  }

  // ─── ProtocolFees overrides ───

  function _isUnlocked() internal pure override returns (bool) {
    return false;
  }

  function _getPool(PoolId id) internal view override returns (Pool.State storage) {
    return _pools[id];
  }

  // ─── IPoolManager stubs (required for casting but not used in tests) ───────

  function unlock(bytes calldata) external pure returns (bytes memory) {
    revert NotSupported();
  }

  function initialize(PoolKey memory, uint160) external pure returns (int24) {
    revert NotSupported();
  }

  function modifyLiquidity(PoolKey memory, ModifyLiquidityParams memory, bytes calldata)
    external
    pure
    returns (BalanceDelta, BalanceDelta)
  {
    revert NotSupported();
  }

  function swap(PoolKey memory, SwapParams memory, bytes calldata)
    external
    pure
    returns (BalanceDelta)
  {
    revert NotSupported();
  }

  function donate(PoolKey memory, uint256, uint256, bytes calldata)
    external
    pure
    returns (BalanceDelta)
  {
    revert NotSupported();
  }

  function sync(Currency) external pure {
    revert NotSupported();
  }

  function take(Currency, address, uint256) external pure {
    revert NotSupported();
  }

  function settle() external payable returns (uint256) {
    revert NotSupported();
  }

  function settleFor(address) external payable returns (uint256) {
    revert NotSupported();
  }

  function clear(Currency, uint256) external pure {
    revert NotSupported();
  }

  function mint(address, uint256, uint256) external pure {
    revert NotSupported();
  }

  function burn(address, uint256, uint256) external pure {
    revert NotSupported();
  }

  function updateDynamicLPFee(PoolKey memory, uint24) external pure {
    revert NotSupported();
  }
}
