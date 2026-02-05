// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Owned} from "solmate/src/auth/Owned.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {IV4FeeAdapter} from "../interfaces/IV4FeeAdapter.sol";

/// @title V4FeeAdapter
/// @notice A protocol fee controller for Uniswap V4 with tiered fee resolution
/// @dev Resolves fees using a waterfall pattern: pool override → fee tier → default
///      This contract must be set as the protocolFeeController on the PoolManager
///
///      Storage encoding:
///      - 0 in storage = "not set" (continue waterfall)
///      - ZERO_FEE_SENTINEL in storage = "explicitly set to zero" (fees disabled)
///      - Any other value = that actual fee
///
/// @custom:security-contact security@uniswap.org
contract V4FeeAdapter is IV4FeeAdapter, Owned {
  using PoolIdLibrary for PoolKey;

  /// @notice Sentinel value stored to represent an explicit zero fee (disabled)
  /// @dev We use type(uint24).max because 0 in storage means "not set" (mapping default)
  uint24 public constant ZERO_FEE_SENTINEL = type(uint24).max;

  /// @inheritdoc IV4FeeAdapter
  IPoolManager public immutable POOL_MANAGER;

  /// @inheritdoc IV4FeeAdapter
  address public immutable TOKEN_JAR;

  /// @inheritdoc IV4FeeAdapter
  address public feeSetter;

  /// @inheritdoc IV4FeeAdapter
  uint24 public defaultFee;

  /// @inheritdoc IV4FeeAdapter
  mapping(uint24 lpFee => uint24 protocolFee) public feeTierOverrides;

  /// @inheritdoc IV4FeeAdapter
  mapping(PoolId poolId => uint24 protocolFee) public poolOverrides;

  /// @notice Ensures only the fee setter can call restricted functions
  modifier onlyFeeSetter() {
    if (msg.sender != feeSetter) revert Unauthorized();
    _;
  }

  /// @param _poolManager The Uniswap V4 PoolManager contract
  /// @param _tokenJar The address where collected fees are sent
  /// @param _feeSetter The address authorized to set fees
  /// @param _defaultFee The default protocol fee (pass ZERO_FEE_SENTINEL to explicitly disable,
  ///        or leave as 0 for "not set")
  constructor(address _poolManager, address _tokenJar, address _feeSetter, uint24 _defaultFee) Owned(msg.sender) {
    if (_defaultFee != 0) _validateFee(_defaultFee);
    POOL_MANAGER = IPoolManager(_poolManager);
    TOKEN_JAR = _tokenJar;
    feeSetter = _feeSetter;
    defaultFee = _defaultFee;
  }

  /// @inheritdoc IV4FeeAdapter
  /// @dev Returns the fee packed for BOTH swap directions (symmetric fee).
  ///      V4 protocol fees are a uint24 where lower 12 bits = zeroForOne fee,
  ///      upper 12 bits = oneForZero fee. We apply the same fee to both directions.
  function getFee(PoolKey memory key) public view returns (uint24 fee) {
    uint24 stored;

    // 1. Pool override (most specific)
    stored = poolOverrides[key.toId()];
    if (stored != 0) return _packFee(_decodeFee(stored));

    // 2. Fee tier override
    stored = feeTierOverrides[key.fee];
    if (stored != 0) return _packFee(_decodeFee(stored));

    // 3. Default fee
    stored = defaultFee;
    if (stored != 0) return _packFee(_decodeFee(stored));

    // Nothing set → no protocol fee
    return 0;
  }

  /// @inheritdoc IV4FeeAdapter
  function applyFee(PoolKey memory key) external {
    POOL_MANAGER.setProtocolFee(key, getFee(key));
  }

  /// @inheritdoc IV4FeeAdapter
  function batchApplyFees(PoolKey[] calldata keys) external {
    uint256 length = keys.length;
    for (uint256 i; i < length; ++i) {
      POOL_MANAGER.setProtocolFee(keys[i], getFee(keys[i]));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //                           SETTERS
  // ═══════════════════════════════════════════════════════════════

  /// @inheritdoc IV4FeeAdapter
  function setDefaultFee(uint24 fee) external onlyFeeSetter {
    _validateFee(fee);
    defaultFee = _encodeFee(fee);
    emit DefaultFeeUpdated(fee);
  }

  /// @inheritdoc IV4FeeAdapter
  function setFeeTierOverride(uint24 lpFee, uint24 protocolFee) external onlyFeeSetter {
    _validateFee(protocolFee);
    feeTierOverrides[lpFee] = _encodeFee(protocolFee);
    emit FeeTierOverrideUpdated(lpFee, protocolFee);
  }

  /// @inheritdoc IV4FeeAdapter
  function setPoolOverride(PoolId poolId, uint24 protocolFee) external onlyFeeSetter {
    _validateFee(protocolFee);
    poolOverrides[poolId] = _encodeFee(protocolFee);
    emit PoolOverrideUpdated(poolId, protocolFee);
  }

  /// @inheritdoc IV4FeeAdapter
  function clearFeeTierOverride(uint24 lpFee) external onlyFeeSetter {
    delete feeTierOverrides[lpFee];
    emit FeeTierOverrideUpdated(lpFee, 0);
  }

  /// @inheritdoc IV4FeeAdapter
  function clearPoolOverride(PoolId poolId) external onlyFeeSetter {
    delete poolOverrides[poolId];
    emit PoolOverrideUpdated(poolId, 0);
  }

  /// @inheritdoc IV4FeeAdapter
  function setFeeSetter(address newFeeSetter) external onlyOwner {
    feeSetter = newFeeSetter;
    emit FeeSetterUpdated(newFeeSetter);
  }

  // ═══════════════════════════════════════════════════════════════
  //                       FEE COLLECTION
  // ═══════════════════════════════════════════════════════════════

  /// @inheritdoc IV4FeeAdapter
  function collectProtocolFees(Currency currency, uint256 amount)
    external
    onlyOwner
    returns (uint256 amountCollected)
  {
    return POOL_MANAGER.collectProtocolFees(TOKEN_JAR, currency, amount);
  }

  // ═══════════════════════════════════════════════════════════════
  //                         INTERNAL
  // ═══════════════════════════════════════════════════════════════

  /// @notice Validates that a protocol fee is within bounds
  /// @param fee The fee to validate in pips (single direction, not packed)
  function _validateFee(uint24 fee) internal pure {
    // 0 is valid (disables protocol fee)
    // Otherwise must be <= MAX_PROTOCOL_FEE (1000 pips = 0.1%)
    if (fee != 0 && fee > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) {
      revert ProtocolFeeTooLarge(fee);
    }
  }

  /// @notice Encodes a fee for storage
  /// @dev Converts 0 to ZERO_FEE_SENTINEL so we can distinguish from "not set"
  /// @param fee The actual fee value
  /// @return The encoded value to store
  function _encodeFee(uint24 fee) internal pure returns (uint24) {
    return fee == 0 ? ZERO_FEE_SENTINEL : fee;
  }

  /// @notice Decodes a fee from storage
  /// @dev Converts ZERO_FEE_SENTINEL back to 0
  /// @param stored The value from storage
  /// @return The actual fee value
  function _decodeFee(uint24 stored) internal pure returns (uint24) {
    return stored == ZERO_FEE_SENTINEL ? 0 : stored;
  }

  /// @notice Packs a single-direction fee into the V4 protocol fee format for both directions
  /// @dev V4 protocol fee is a uint24: lower 12 bits = zeroForOne, upper 12 bits = oneForZero
  /// @param fee The fee in pips (0-1000 range for single direction)
  /// @return The packed fee value for symmetric application to both swap directions
  function _packFee(uint24 fee) internal pure returns (uint24) {
    // Pack fee into both directions: (oneForZero << 12) | zeroForOne
    return (fee << 12) | fee;
  }
}
