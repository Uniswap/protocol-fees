// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Owned} from "solmate/src/auth/Owned.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {LibBit} from "solady/src/utils/LibBit.sol";
import {IV4FeePolicy, FlagRule, FeeBucket} from "../interfaces/IV4FeePolicy.sol";
import {IFeeClassifiedHook} from "../interfaces/IFeeClassifiedHook.sol";

/// @title V4FeePolicy
/// @notice Computes protocol fees for Uniswap V4 pools using automated hook classification
/// and a piecewise-linear schedule of fee buckets.
/// @dev Pools are classified into two paths:
/// - StaticNativeMath: no RETURNS_DELTA flags and static fee →
///   `pairClassFees[pair][NATIVE_MATH_FAMILY_ID]`, else evaluate the fee-bucket schedule.
/// - Classified: custom accounting or dynamic fee → resolve family, then
///   `pairClassFees[pair][family]` → `familyDefaults[family]` → `defaultFee`.
/// Hook classification is automated from address bits 0-3 (RETURNS_DELTA flags).
/// Hooks can self-report behavioral flags via IFeeClassifiedHook.protocolFeeFlags().
/// Governance-configured flag rules map flag patterns to families automatically.
/// Priority: governance override → flag-rule match on self-reported flags → defaultFee.
/// @custom:security-contact security@uniswap.org
contract V4FeePolicy is IV4FeePolicy, Owned {
  using LPFeeLibrary for uint24;

  /// @inheritdoc IV4FeePolicy
  uint8 public constant NATIVE_MATH_FAMILY_ID = 0;

  /// @dev Bitmask for the four RETURNS_DELTA flags (bits 0-3 of hook address).
  uint160 public constant CUSTOM_ACCOUNTING_MASK = 0xF;

  /// @dev Gas limit for hook self-report calls. Prevents griefing in batch operations.
  uint256 internal constant SELF_REPORT_GAS_LIMIT = 30_000;

  /// @dev Sentinel value: stored to represent an explicit zero fee. type(uint24).max is
  /// safe because each 12-bit component (0xFFF = 4095) exceeds MAX_PROTOCOL_FEE (1000).
  uint24 internal constant ZERO_FEE_SENTINEL = type(uint24).max;

  /// @dev Shared denominator for pips-based bucket slopes. 1_000_000 = 100% (matches the
  /// v4-core LP fee denominator).
  uint24 internal constant MULTIPLIER_DENOMINATOR = LPFeeLibrary.MAX_LP_FEE;

  /// @dev Maximum number of fee buckets. Bounds the backward walk in
  /// `_computeStaticNativeMathFee`.
  uint256 internal constant MAX_BUCKETS = 16;

  /// @dev Maximum `betaPips` per bucket. Above this, even a 1-pip delta exceeds
  /// MAX_PROTOCOL_FEE, so the per-direction clamp is always hit and values above are
  /// functionally identical noise.
  uint32 internal constant MAX_BETA_PIPS =
    uint32(uint256(MULTIPLIER_DENOMINATOR) * ProtocolFeeLibrary.MAX_PROTOCOL_FEE);

  /// @inheritdoc IV4FeePolicy
  IPoolManager public immutable POOL_MANAGER;

  /// @inheritdoc IV4FeePolicy
  address public feeSetter;

  /// @inheritdoc IV4FeePolicy
  uint24 public defaultFee;

  /// @inheritdoc IV4FeePolicy
  mapping(address hook => uint8) public hookFamilyId;

  /// @inheritdoc IV4FeePolicy
  mapping(uint8 familyId => uint24) public familyDefaults;

  /// @inheritdoc IV4FeePolicy
  mapping(bytes32 pairHash => mapping(uint8 familyId => uint24)) public pairClassFees;

  /// @dev Ordered fee buckets for the StaticNativeMath path. Ascending by
  /// `lpFeeFloor`. Set atomically via `setFeeBuckets`. Empty array → Path A returns 0
  /// when no native pair class fee override exists.
  FeeBucket[] internal _feeBuckets;

  /// @dev Maximum number of flag rules to bound gas in _resolveFamily.
  uint256 internal constant MAX_FLAG_RULES = 32;

  /// @dev Ordered flag rules for mapping self-reported hook flags to family IDs.
  /// First matching rule wins. Set atomically via setFlagRules().
  FlagRule[] internal _flagRules;

  /// @notice Restricts access to the fee setter address.
  modifier onlyFeeSetter() {
    if (msg.sender != feeSetter) revert Unauthorized();
    _;
  }

  /// @notice Constructs the V4FeePolicy with a reference to the PoolManager.
  /// @param poolManager The Uniswap V4 PoolManager this policy reads state from.
  constructor(IPoolManager poolManager) Owned(msg.sender) {
    POOL_MANAGER = poolManager;
  }

  // ─── Pure Classification ───

  /// @inheritdoc IV4FeePolicy
  function isCustomAccounting(address hook) external pure returns (bool) {
    return _isCustomAccounting(hook);
  }

  // ─── Fee Computation ───

  /// @inheritdoc IV4FeePolicy
  function computeFee(PoolKey calldata key) external view returns (uint24) {
    address hook = address(key.hooks);
    bytes32 ph = _pairHash(key.currency0, key.currency1);

    // StaticNativeMath: no custom accounting + static fee
    if (!_isCustomAccounting(hook) && !key.fee.isDynamicFee()) {
      uint24 stored = pairClassFees[ph][NATIVE_MATH_FAMILY_ID];
      if (stored != 0) return _decodeFee(stored);
      return _computeStaticNativeMathFee(key.fee);
    }

    // Classified: custom accounting OR dynamic fee
    uint8 family = _resolveFamily(hook);
    if (family == 0) return _decodeFee(defaultFee);

    uint24 pairStored = pairClassFees[ph][family];
    if (pairStored != 0) return _decodeFee(pairStored);

    uint24 famDefault = familyDefaults[family];
    if (famDefault != 0) return _decodeFee(famDefault);

    return _decodeFee(defaultFee);
  }

  // ─── Flag Rules Getters ───

  /// @inheritdoc IV4FeePolicy
  function flagRulesLength() external view returns (uint256) {
    return _flagRules.length;
  }

  /// @inheritdoc IV4FeePolicy
  function flagRules(uint256 index) external view returns (uint256 requiredFlags, uint8 familyId) {
    FlagRule storage rule = _flagRules[index];
    return (rule.requiredFlags, rule.familyId);
  }

  // ─── Fee Bucket Getters ───

  /// @inheritdoc IV4FeePolicy
  function feeBucketsLength() external view returns (uint256) {
    return _feeBuckets.length;
  }

  /// @inheritdoc IV4FeePolicy
  function feeBucket(uint256 index)
    external
    view
    returns (uint24 lpFeeFloor, uint24 alphaPips, uint32 betaPips)
  {
    FeeBucket storage b = _feeBuckets[index];
    return (b.lpFeeFloor, b.alphaPips, b.betaPips);
  }

  // ─── Admin ───

  /// @inheritdoc IV4FeePolicy
  function setFeeSetter(address newFeeSetter) external onlyOwner {
    emit FeeSetterUpdated(feeSetter, newFeeSetter);
    feeSetter = newFeeSetter;
  }

  // ─── Configuration (onlyFeeSetter) ───

  /// @inheritdoc IV4FeePolicy
  function setHookFamily(address hook, uint8 familyId) external onlyFeeSetter {
    hookFamilyId[hook] = familyId;
    emit HookFamilySet(hook, familyId);
  }

  /// @inheritdoc IV4FeePolicy
  function setFlagRules(FlagRule[] calldata rules) external onlyFeeSetter {
    if (rules.length > MAX_FLAG_RULES) revert TooManyFlagRules();

    delete _flagRules;

    uint256 previousSpecificity = type(uint256).max;
    for (uint256 i; i < rules.length; ++i) {
      FlagRule calldata rule = rules[i];
      if (rule.requiredFlags == 0 || rule.familyId == 0) revert InvalidFlagRule();
      uint256 specificity = LibBit.popCount(rule.requiredFlags);
      if (specificity > previousSpecificity) revert FlagRulesNotSorted();
      previousSpecificity = specificity;
      _flagRules.push(rule);
    }

    emit FlagRulesUpdated(rules.length);
  }

  /// @inheritdoc IV4FeePolicy
  function clearFlagRules() external onlyFeeSetter {
    delete _flagRules;
    emit FlagRulesUpdated(0);
  }

  /// @inheritdoc IV4FeePolicy
  function setDefaultFee(uint24 feeValue) external onlyFeeSetter {
    if (feeValue != 0) _validateFee(feeValue);
    uint24 stored = _encodeFee(feeValue);
    defaultFee = stored;
    emit DefaultFeeUpdated(stored);
  }

  /// @inheritdoc IV4FeePolicy
  function clearDefaultFee() external onlyFeeSetter {
    delete defaultFee;
    emit DefaultFeeUpdated(0);
  }

  /// @inheritdoc IV4FeePolicy
  function setFeeBuckets(FeeBucket[] calldata buckets) external onlyFeeSetter {
    uint256 len = buckets.length;
    if (len == 0) revert EmptyBuckets();
    if (len > MAX_BUCKETS) revert TooManyBuckets();

    delete _feeBuckets;

    uint24 prevFloor;
    for (uint256 i; i < len; ++i) {
      FeeBucket calldata b = buckets[i];
      if (i > 0 && b.lpFeeFloor <= prevFloor) revert BucketsNotAscending();
      if (b.alphaPips > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) revert InvalidFeeValue();
      if (b.betaPips > MAX_BETA_PIPS) revert MultiplierTooLarge();
      _feeBuckets.push(b);
      prevFloor = b.lpFeeFloor;
    }

    emit FeeBucketsUpdated(len);
  }

  /// @inheritdoc IV4FeePolicy
  function clearFeeBuckets() external onlyFeeSetter {
    delete _feeBuckets;
    emit FeeBucketsUpdated(0);
  }

  /// @inheritdoc IV4FeePolicy
  function setFamilyDefault(uint8 familyId, uint24 feeValue) external onlyFeeSetter {
    if (familyId == 0) revert InvalidFamilyId();
    if (feeValue != 0) _validateFee(feeValue);
    uint24 stored = _encodeFee(feeValue);
    familyDefaults[familyId] = stored;
    emit FamilyDefaultUpdated(familyId, stored);
  }

  /// @inheritdoc IV4FeePolicy
  function clearFamilyDefault(uint8 familyId) external onlyFeeSetter {
    delete familyDefaults[familyId];
    emit FamilyDefaultUpdated(familyId, 0);
  }

  /// @inheritdoc IV4FeePolicy
  function setPairClassFee(
    Currency currency0,
    Currency currency1,
    uint8 familyId,
    uint24 feeValue
  ) external onlyFeeSetter {
    if (currency0 >= currency1) revert CurrenciesOutOfOrder();
    if (feeValue != 0) _validateFee(feeValue);
    bytes32 ph = _pairHash(currency0, currency1);
    uint24 stored = _encodeFee(feeValue);
    pairClassFees[ph][familyId] = stored;
    emit PairClassFeeUpdated(ph, familyId, stored);
  }

  /// @inheritdoc IV4FeePolicy
  function clearPairClassFee(Currency currency0, Currency currency1, uint8 familyId)
    external
    onlyFeeSetter
  {
    if (currency0 >= currency1) revert CurrenciesOutOfOrder();
    bytes32 ph = _pairHash(currency0, currency1);
    delete pairClassFees[ph][familyId];
    emit PairClassFeeUpdated(ph, familyId, 0);
  }

  // ─── Internal ───

  /// @dev Returns true if the hook address has any RETURNS_DELTA flag set (bits 0-3).
  function _isCustomAccounting(address hook) internal pure returns (bool) {
    return uint160(hook) & CUSTOM_ACCOUNTING_MASK != 0;
  }

  /// @dev Resolves the family ID for a hook: governance override, then flag rules.
  function _resolveFamily(address hook) internal view returns (uint8) {
    uint8 gov = hookFamilyId[hook];
    if (gov != 0) return gov;

    uint256 rulesLen = _flagRules.length;
    if (rulesLen == 0) return 0;

    uint256 flags;
    bool ok;
    uint256 gasLimit = SELF_REPORT_GAS_LIMIT;
    uint256 selector = uint32(IFeeClassifiedHook.protocolFeeFlags.selector);
    assembly ("memory-safe") {
      let ptr := mload(0x40)
      mstore(ptr, shl(224, selector))
      ok := staticcall(gasLimit, hook, ptr, 0x04, ptr, 0x20)
      ok := and(ok, iszero(lt(returndatasize(), 0x20)))
      flags := mload(ptr)
    }
    if (ok && flags != 0) {
      for (uint256 i; i < rulesLen; ++i) {
        FlagRule storage rule = _flagRules[i];
        uint256 requiredFlags = rule.requiredFlags;
        if (flags & requiredFlags == requiredFlags) return rule.familyId;
      }
    }

    return 0;
  }

  /// @dev Canonical hash for a sorted token pair.
  function _pairHash(Currency c0, Currency c1) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(Currency.unwrap(c0), Currency.unwrap(c1)));
  }

  /// @dev Piecewise-linear fee from `_feeBuckets` for StaticNativeMath pools.
  function _computeStaticNativeMathFee(uint24 lpFee) internal view returns (uint24) {
    uint256 len = _feeBuckets.length;
    if (len == 0) return 0;

    FeeBucket memory bucket = _feeBuckets[0];
    for (uint256 i = len; i > 1; --i) {
      FeeBucket memory candidate = _feeBuckets[i - 1];
      if (candidate.lpFeeFloor <= lpFee) {
        bucket = candidate;
        break;
      }
    }

    uint256 delta = lpFee >= bucket.lpFeeFloor ? lpFee - bucket.lpFeeFloor : 0;
    uint256 perDirection =
      uint256(bucket.alphaPips) + uint256(bucket.betaPips) * delta / MULTIPLIER_DENOMINATOR;
    if (perDirection > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) {
      perDirection = ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
    }
    return uint24((perDirection << 12) | perDirection);
  }

  /// @dev Encodes a fee for storage. Converts 0 to ZERO_FEE_SENTINEL.
  function _encodeFee(uint24 feeValue) internal pure returns (uint24) {
    return feeValue == 0 ? ZERO_FEE_SENTINEL : feeValue;
  }

  /// @dev Decodes a fee from storage.
  function _decodeFee(uint24 stored) internal pure returns (uint24) {
    return stored == ZERO_FEE_SENTINEL ? 0 : stored;
  }

  /// @dev Validates protocol fee bounds.
  function _validateFee(uint24 feeValue) internal pure {
    if (!ProtocolFeeLibrary.isValidProtocolFee(feeValue)) revert InvalidFeeValue();
  }
}
