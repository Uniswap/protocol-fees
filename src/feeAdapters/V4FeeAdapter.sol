// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Owned} from "solmate/src/auth/Owned.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {IV4FeeAdapter} from "../interfaces/IV4FeeAdapter.sol";
import {IV4FeePolicy} from "../interfaces/IV4FeePolicy.sol";

/// @title V4FeeAdapter
/// @notice The protocolFeeController for the Uniswap V4 PoolManager. Resolves fees via a
/// waterfall (pool override → policy → 0), pushes them to the PoolManager, and collects
/// accrued fees to the TokenJar.
/// @dev The adapter is the trusted, long-lived piece. The policy is replaceable by the owner.
/// @custom:security-contact security@uniswap.org
contract V4FeeAdapter is IV4FeeAdapter, Owned {
  using PoolIdLibrary for PoolKey;
  using StateLibrary for IPoolManager;

  /// @dev Sentinel value: stored to represent an explicit zero fee. type(uint24).max is
  /// safe because each 12-bit component (0xFFF = 4095) exceeds MAX_PROTOCOL_FEE (1000).
  uint24 public constant ZERO_FEE_SENTINEL = type(uint24).max;

  /// @inheritdoc IV4FeeAdapter
  IPoolManager public immutable POOL_MANAGER;

  /// @inheritdoc IV4FeeAdapter
  address public immutable TOKEN_JAR;

  /// @inheritdoc IV4FeeAdapter
  address public feeSetter;

  /// @inheritdoc IV4FeeAdapter
  IV4FeePolicy public policy;

  /// @inheritdoc IV4FeeAdapter
  mapping(PoolId poolId => uint24) public poolOverrides;

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
  function getFee(PoolKey memory key) public view returns (uint24) {
    uint24 stored = poolOverrides[key.toId()];
    if (stored != 0) return _decodeFee(stored);
    if (address(policy) == address(0)) return 0;
    return policy.computeFee(key);
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
  function setPoolOverride(PoolId poolId, uint24 feeValue) external onlyFeeSetter {
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
  /// @param key The pool key identifying the pool to update.
  function _setProtocolFee(PoolKey memory key) internal {
    PoolId id = key.toId();

    // Check pool is initialized (sqrtPriceX96 != 0) before calling PoolManager
    (uint160 sqrtPriceX96,,,) = POOL_MANAGER.getSlot0(id);
    if (sqrtPriceX96 == 0) return;

    uint24 feeValue = getFee(key);
    POOL_MANAGER.setProtocolFee(key, feeValue);
    emit FeeUpdateTriggered(msg.sender, id, feeValue);
  }

  /// @dev Encodes a fee for storage. Converts 0 to ZERO_FEE_SENTINEL so that 0 in
  /// storage means "not set" rather than "explicitly zero".
  /// @param feeValue The actual fee value (0 = remove/unset).
  /// @return The encoded value to store.
  function _encodeFee(uint24 feeValue) internal pure returns (uint24) {
    return feeValue == 0 ? ZERO_FEE_SENTINEL : feeValue;
  }

  /// @dev Decodes a fee from storage. Converts ZERO_FEE_SENTINEL back to 0.
  /// @param stored The raw value from storage.
  /// @return The actual fee value.
  function _decodeFee(uint24 stored) internal pure returns (uint24) {
    return stored == ZERO_FEE_SENTINEL ? 0 : stored;
  }

  /// @dev Validates that a protocol fee is within v4-core bounds (each 12-bit directional
  /// component must be <= MAX_PROTOCOL_FEE = 1000).
  /// @param feeValue The fee to validate.
  function _validateFee(uint24 feeValue) internal pure {
    if (!ProtocolFeeLibrary.isValidProtocolFee(feeValue)) revert InvalidFeeValue();
  }
}
