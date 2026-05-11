// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Owned} from "solmate/src/auth/Owned.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {IV4FeeAdapter} from "../interfaces/IV4FeeAdapter.sol";
import {IV4FeePolicy} from "../interfaces/IV4FeePolicy.sol";

/// @title V4FeeAdapter
/// @notice The protocolFeeController for the Uniswap V4 PoolManager. Resolves fees via a
/// waterfall (pool override → policy → 0), pushes them to the PoolManager, and collects
/// accrued fees to the TokenJar.
/// @dev The adapter is the trusted, long-lived piece. The policy is replaceable by the owner.
///
/// Fees are stored internally as uint48 packed `(fee1to0 << 24) | fee0to1`, with each
/// 24-bit half bounded by MAX_LP_FEE (1_000_000). The manager-push path clamps each
/// half to MAX_PROTOCOL_FEE (1000) and repacks as uint24 (12+12) before calling
/// PoolManager.setProtocolFee, so `getFee` keeps its uint24 return type for off-chain
/// backwards compatibility. `getFeeRaw` exposes the uncapped uint48 for callers that
/// understand the wider representation.
/// @custom:security-contact security@uniswap.org
contract V4FeeAdapter is IV4FeeAdapter, Owned {
  using PoolIdLibrary for PoolKey;
  using StateLibrary for IPoolManager;

  /// @dev Sentinel value: stored to represent an explicit zero fee. type(uint48).max is
  /// safe because each 24-bit component (0xFFFFFF = 16_777_215) exceeds MAX_LP_FEE
  /// (1_000_000), so _validateFee rejects it.
  uint48 public constant ZERO_FEE_SENTINEL = type(uint48).max;

  /// @dev Bitmask for the four RETURNS_DELTA flags (bits 0-3 of hook address).
  /// INVARIANT: keep in sync with V4FeePolicy.CUSTOM_ACCOUNTING_MASK and v4-core's
  /// hook RETURNS_DELTA bit layout. Duplicated locally (not imported from policy)
  /// to avoid an external SLOAD on a hot path and a reentrancy surface across the
  /// adapter/policy boundary.
  uint160 internal constant CUSTOM_ACCOUNTING_MASK = 0xF;

  /// @inheritdoc IV4FeeAdapter
  IPoolManager public immutable POOL_MANAGER;

  /// @inheritdoc IV4FeeAdapter
  address public immutable TOKEN_JAR;

  /// @inheritdoc IV4FeeAdapter
  address public feeSetter;

  /// @inheritdoc IV4FeeAdapter
  IV4FeePolicy public policy;

  /// @inheritdoc IV4FeeAdapter
  mapping(PoolId poolId => uint48) public poolOverrides;

  /// @notice Restricts access to the fee setter address.
  modifier onlyFeeSetter() {
    if (msg.sender != feeSetter) revert Unauthorized();
    _;
  }

  /// @notice Constructs the V4FeeAdapter with immutable references to the PoolManager and
  /// TokenJar. The deployer becomes the initial owner.
  /// @param poolManager The Uniswap V4 PoolManager this adapter is the protocolFeeController
  /// for. Must be registered via PoolManager.setProtocolFeeController() after deployment.
  /// @param tokenJar The address where all collected protocol fees are sent.
  constructor(IPoolManager poolManager, address tokenJar) Owned(msg.sender) {
    POOL_MANAGER = poolManager;
    TOKEN_JAR = tokenJar;
  }

  // ─── Fee Resolution ───

  /// @inheritdoc IV4FeeAdapter
  function getFeeRaw(PoolKey memory key) public view returns (uint48) {
    uint48 stored = poolOverrides[key.toId()];
    if (stored != 0) return _decodeFee(stored);
    if (address(policy) == address(0)) return 0;
    return policy.computeFee(key);
  }

  /// @inheritdoc IV4FeeAdapter
  function getFee(PoolKey memory key) public view returns (uint24) {
    return _clampAndPackForManager(getFeeRaw(key));
  }

  /// @inheritdoc IV4FeeAdapter
  function getCustomAccountingFee(PoolKey memory key) external view returns (uint48 feePacked) {
    if (uint160(address(key.hooks)) & CUSTOM_ACCOUNTING_MASK == 0) return 0;
    return getFeeRaw(key);
  }

  // ─── Permissionless Triggering ───

  /// @inheritdoc IV4FeeAdapter
  function triggerFeeUpdate(PoolKey calldata key) external {
    _setProtocolFee(key);
  }

  /// @inheritdoc IV4FeeAdapter
  function batchTriggerFeeUpdate(PoolKey[] calldata keys) external {
    for (uint256 i; i < keys.length; ++i) {
      _setProtocolFee(keys[i]);
    }
  }

  // ─── Collection ───

  /// @inheritdoc IV4FeeAdapter
  function collect(CollectParams[] calldata params) external {
    uint256 length = params.length;
    for (uint256 i; i < length; ++i) {
      CollectParams calldata p = params[i];
      uint256 collected = POOL_MANAGER.collectProtocolFees(TOKEN_JAR, p.currency, p.amount);
      emit FeesCollected(p.currency, collected);
    }
  }

  // ─── Admin (onlyOwner) ───

  /// @inheritdoc IV4FeeAdapter
  function setPolicy(IV4FeePolicy newPolicy) external onlyOwner {
    emit PolicyUpdated(address(policy), address(newPolicy));
    policy = newPolicy;
  }

  /// @inheritdoc IV4FeeAdapter
  function setFeeSetter(address newFeeSetter) external onlyOwner {
    emit FeeSetterUpdated(feeSetter, newFeeSetter);
    feeSetter = newFeeSetter;
  }

  // ─── Pool Overrides (onlyFeeSetter) ───

  /// @inheritdoc IV4FeeAdapter
  function setPoolOverride(PoolId poolId, uint48 feeValue) external onlyFeeSetter {
    if (feeValue != 0) _validateFee(feeValue);
    poolOverrides[poolId] = _encodeFee(feeValue);
    emit PoolOverrideUpdated(poolId, feeValue);
  }

  /// @inheritdoc IV4FeeAdapter
  function clearPoolOverride(PoolId poolId) external onlyFeeSetter {
    delete poolOverrides[poolId];
    emit PoolOverrideUpdated(poolId, 0);
  }

  // ─── Internal ───

  /// @dev Resolves the fee for a pool via the waterfall, checks that the pool is
  /// initialized, and pushes the fee to the PoolManager. Silently skips uninitialized
  /// pools (sqrtPriceX96 == 0) to avoid a revert from the PoolManager and save gas.
  /// Pushes the clamped-and-packed uint24 representation; the raw uint48 stays accessible
  /// via `getFeeRaw` for callers that need the uncapped value.
  /// @param key The pool key identifying the pool to update.
  function _setProtocolFee(PoolKey memory key) internal {
    PoolId id = key.toId();

    // Check pool is initialized (sqrtPriceX96 != 0) before calling PoolManager
    (uint160 sqrtPriceX96,,,) = POOL_MANAGER.getSlot0(id);
    if (sqrtPriceX96 == 0) return;

    // Custom-accounting hooks read their fee directly from this adapter via
    // getCustomAccountingFee. Push 0 so off-chain readers see a deterministic
    // state and stale Slot0 values don't mislead.
    // This bypasses the pool-override waterfall: an explicit poolOverrides[id]
    // is ignored for custom-accounting pools, since the manager-side fee is
    // structurally unused for them.
    bool isCustomAccounting = uint160(address(key.hooks)) & CUSTOM_ACCOUNTING_MASK != 0;
    uint24 feeValue = isCustomAccounting ? 0 : getFee(key);
    POOL_MANAGER.setProtocolFee(key, feeValue);
    emit FeeUpdateTriggered(msg.sender, id, feeValue);
  }

  /// @dev Clamps each 24-bit half of a raw uint48 fee to MAX_PROTOCOL_FEE and packs the
  /// result as a uint24 (12+12) suitable for PoolManager.setProtocolFee.
  /// @param raw The raw uint48 fee (each 24-bit half <= MAX_LP_FEE).
  /// @return The clamped uint24 fee (each 12-bit half <= MAX_PROTOCOL_FEE).
  function _clampAndPackForManager(uint48 raw) internal pure returns (uint24) {
    uint256 fee0 = uint256(raw) & 0xFFFFFF;
    uint256 fee1 = uint256(raw) >> 24;
    if (fee0 > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) fee0 = ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
    if (fee1 > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) fee1 = ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
    return uint24((fee1 << 12) | fee0);
  }

  /// @dev Encodes a fee for storage. Converts 0 to ZERO_FEE_SENTINEL so that 0 in
  /// storage means "not set" rather than "explicitly zero".
  /// @param feeValue The actual fee value (0 = remove/unset).
  /// @return The encoded value to store.
  function _encodeFee(uint48 feeValue) internal pure returns (uint48) {
    return feeValue == 0 ? ZERO_FEE_SENTINEL : feeValue;
  }

  /// @dev Decodes a fee from storage. Converts ZERO_FEE_SENTINEL back to 0.
  /// @param stored The raw value from storage.
  /// @return The actual fee value.
  function _decodeFee(uint48 stored) internal pure returns (uint48) {
    return stored == ZERO_FEE_SENTINEL ? 0 : stored;
  }

  /// @dev Validates that a protocol fee is within structural bounds: each 24-bit
  /// directional component must be <= LPFeeLibrary.MAX_LP_FEE (1_000_000). Wider than
  /// the manager-push path's MAX_PROTOCOL_FEE; clamping happens in
  /// _clampAndPackForManager.
  /// @param feeValue The fee to validate.
  function _validateFee(uint48 feeValue) internal pure {
    uint256 fee0 = uint256(feeValue) & 0xFFFFFF;
    uint256 fee1 = uint256(feeValue) >> 24;
    if (fee0 > LPFeeLibrary.MAX_LP_FEE || fee1 > LPFeeLibrary.MAX_LP_FEE) revert InvalidFeeValue();
  }
}
