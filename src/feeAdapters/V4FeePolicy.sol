// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Owned} from "solmate/src/auth/Owned.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {IV4FeePolicy, CurveBreakpoint, FlagRule} from "../interfaces/IV4FeePolicy.sol";
import {IFeeClassifiedHook} from "../interfaces/IFeeClassifiedHook.sol";

/// @title V4FeePolicy
/// @notice Computes protocol fees for Uniswap V4 pools using automated hook classification
/// and a baseline fee curve.
/// @dev Pools are classified into two paths:
/// - StaticNativeMath: no RETURNS_DELTA flags and static fee → baseline curve or pair fee.
/// - Classified: custom accounting or dynamic fee → family multiplier × pair fee, family
///   default, or global default fee.
/// Hook classification is automated from address bits 0-3 (RETURNS_DELTA flags).
/// Hooks can self-report behavioral flags via IFeeClassifiedHook.protocolFeeFlags().
/// Governance-configured flag rules map flag patterns to families automatically.
/// Priority: governance override → flag-rule match on self-reported flags → defaultFee.
/// @custom:security-contact security@uniswap.org
contract V4FeePolicy is IV4FeePolicy, Owned {
  using LPFeeLibrary for uint24;
  using PoolIdLibrary for PoolKey;

  /// @dev Bitmask for the four RETURNS_DELTA flags (bits 0-3 of hook address).
  uint160 public constant CUSTOM_ACCOUNTING_MASK = 0xF;

  /// @dev Gas limit for hook self-report calls. Prevents griefing in batch operations.
  uint256 internal constant SELF_REPORT_GAS_LIMIT = 30_000;

  /// @dev Sentinel value: stored to represent an explicit zero fee. type(uint24).max is
  /// safe because each 12-bit component (0xFFF = 4095) exceeds MAX_PROTOCOL_FEE (1000).
  uint24 internal constant ZERO_FEE_SENTINEL = type(uint24).max;

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
  mapping(uint8 familyId => uint16) public familyMultiplierBps;

  /// @inheritdoc IV4FeePolicy
  mapping(bytes32 pairHash => uint24) public pairFees;

  /// @dev The baseline curve breakpoints, sorted ascending by lpFeeFloor. Used only by
  /// StaticNativeMath pools to map key.fee to a protocol fee.
  CurveBreakpoint[] internal _baselineCurve;

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
      uint24 stored = pairFees[ph];
      return stored != 0 ? _decodeFee(stored) : _lookupBaselineFee(key.fee);
    }

    // Classified: custom accounting OR dynamic fee
    // Priority: governance override → flag-rule match → unclassified
    uint8 family = _resolveFamily(hook);
    if (family != 0) {
      uint24 pairFee = pairFees[ph];
      uint16 multiplier = familyMultiplierBps[family];

      if (pairFee != 0 && multiplier != 0) {
        return _applyMultiplier(_decodeFee(pairFee), multiplier);
      }

      uint24 famDefault = familyDefaults[family];
      if (famDefault != 0) return _decodeFee(famDefault);
    }

    return _decodeFee(defaultFee);
  }

  // ─── Curve Getters ───

  /// @inheritdoc IV4FeePolicy
  function baselineCurveLength() external view returns (uint256) {
    return _baselineCurve.length;
  }

  /// @inheritdoc IV4FeePolicy
  function baselineCurve(uint256 index)
    external
    view
    returns (uint24 lpFeeFloor, uint24 protocolFee)
  {
    CurveBreakpoint storage bp = _baselineCurve[index];
    return (bp.lpFeeFloor, bp.protocolFee);
  }

  // ─── Flag Rules Getters ───

  /// @inheritdoc IV4FeePolicy
  function flagRulesLength() external view returns (uint256) {
    return _flagRules.length;
  }

  /// @inheritdoc IV4FeePolicy
  function flagRules(uint256 index)
    external
    view
    returns (uint256 requiredFlags, uint8 familyId)
  {
    FlagRule storage rule = _flagRules[index];
    return (rule.requiredFlags, rule.familyId);
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

    for (uint256 i; i < rules.length; ++i) {
      FlagRule calldata rule = rules[i];
      if (rule.requiredFlags == 0 || rule.familyId == 0) revert InvalidFlagRule();
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
    defaultFee = _encodeFee(feeValue);
    emit DefaultFeeUpdated(feeValue);
  }

  /// @inheritdoc IV4FeePolicy
  function clearDefaultFee() external onlyFeeSetter {
    delete defaultFee;
    emit DefaultFeeUpdated(0);
  }

  /// @inheritdoc IV4FeePolicy
  function setBaselineCurve(CurveBreakpoint[] calldata breakpoints) external onlyFeeSetter {
    if (breakpoints.length == 0) revert EmptyCurve();

    // Clear existing curve
    delete _baselineCurve;

    uint24 prevFloor;
    for (uint256 i; i < breakpoints.length; ++i) {
      CurveBreakpoint calldata bp = breakpoints[i];
      if (i != 0 && bp.lpFeeFloor <= prevFloor) revert CurveNotAscending();
      _validateFee(bp.protocolFee);
      _baselineCurve.push(bp);
      prevFloor = bp.lpFeeFloor;
    }

    emit BaselineCurveUpdated(breakpoints.length);
  }

  /// @inheritdoc IV4FeePolicy
  function setFamilyDefault(uint8 familyId, uint24 feeValue) external onlyFeeSetter {
    if (familyId == 0) revert InvalidFamilyId();
    if (feeValue != 0) _validateFee(feeValue);
    familyDefaults[familyId] = _encodeFee(feeValue);
    emit FamilyDefaultUpdated(familyId, feeValue);
  }

  /// @inheritdoc IV4FeePolicy
  function clearFamilyDefault(uint8 familyId) external onlyFeeSetter {
    delete familyDefaults[familyId];
    emit FamilyDefaultUpdated(familyId, 0);
  }

  /// @inheritdoc IV4FeePolicy
  function setFamilyMultiplier(uint8 familyId, uint16 multiplierBps) external onlyFeeSetter {
    if (familyId == 0) revert InvalidFamilyId();
    familyMultiplierBps[familyId] = multiplierBps;
    emit FamilyMultiplierUpdated(familyId, multiplierBps);
  }

  /// @inheritdoc IV4FeePolicy
  function clearFamilyMultiplier(uint8 familyId) external onlyFeeSetter {
    delete familyMultiplierBps[familyId];
    emit FamilyMultiplierUpdated(familyId, 0);
  }

  /// @inheritdoc IV4FeePolicy
  function setPairFee(Currency currency0, Currency currency1, uint24 feeValue)
    external
    onlyFeeSetter
  {
    if (Currency.unwrap(currency0) >= Currency.unwrap(currency1)) {
      revert CurrenciesOutOfOrder();
    }
    if (feeValue != 0) _validateFee(feeValue);
    bytes32 ph = _pairHash(currency0, currency1);
    pairFees[ph] = _encodeFee(feeValue);
    emit PairFeeUpdated(ph, feeValue);
  }

  /// @inheritdoc IV4FeePolicy
  function clearPairFee(Currency currency0, Currency currency1) external onlyFeeSetter {
    if (Currency.unwrap(currency0) >= Currency.unwrap(currency1)) revert CurrenciesOutOfOrder();
    bytes32 ph = _pairHash(currency0, currency1);
    delete pairFees[ph];
    emit PairFeeUpdated(ph, 0);
  }

  // ─── Internal ───

  /// @dev Returns true if the hook address has any RETURNS_DELTA flag set (bits 0-3).
  /// This is a pure function of the address — the flags are baked into the address at
  /// CREATE2 deployment time and cannot change.
  /// @param hook The hook contract address to check.
  /// @return True if any of the four RETURNS_DELTA bits are set.
  function _isCustomAccounting(address hook) internal pure returns (bool) {
    return uint160(hook) & CUSTOM_ACCOUNTING_MASK != 0;
  }

  /// @dev Resolves the family ID for a hook using a priority chain:
  /// 1. Governance override (hookFamilyId[hook]) — always wins if non-zero.
  /// 2. Flag-rule match: gas-capped staticcall to protocolFeeFlags(), then walk
  ///    _flagRules in order. First rule whose requiredFlags are all present wins.
  /// 3. Returns 0 (unclassified) if neither source provides a family.
  /// @param hook The hook contract address to resolve.
  /// @return The resolved family ID, or 0 if unclassified.
  function _resolveFamily(address hook) internal view returns (uint8) {
    uint8 gov = hookFamilyId[hook];
    if (gov != 0) return gov;

    uint256 rulesLen = _flagRules.length;
    if (rulesLen == 0) return 0;

    (bool ok, bytes memory ret) = hook.staticcall{gas: SELF_REPORT_GAS_LIMIT}(
      abi.encodeCall(IFeeClassifiedHook.protocolFeeFlags, ())
    );
    if (ok && ret.length >= 32) {
      uint256 flags = abi.decode(ret, (uint256));
      if (flags != 0) {
        for (uint256 i; i < rulesLen; ++i) {
          FlagRule storage rule = _flagRules[i];
          if (flags & rule.requiredFlags == rule.requiredFlags) {
            return rule.familyId;
          }
        }
      }
    }

    return 0;
  }

  /// @dev Computes a canonical hash for a token pair. Assumes c0 < c1 (guaranteed by
  /// PoolKey sorting invariant). Used as the key for pairFees lookups.
  /// @param c0 The lower currency address.
  /// @param c1 The higher currency address.
  /// @return The keccak256 hash of the packed currency addresses.
  function _pairHash(Currency c0, Currency c1) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(Currency.unwrap(c0), Currency.unwrap(c1)));
  }

  /// @dev Walks the baseline curve backward to find the highest floor <= lpFee.
  /// Returns 0 if the curve is empty or no breakpoint qualifies.
  /// @param lpFee The pool's LP fee in pips (from key.fee for static fee pools).
  /// @return The protocol fee from the matching breakpoint, or 0.
  function _lookupBaselineFee(uint24 lpFee) internal view returns (uint24) {
    uint256 len = _baselineCurve.length;
    if (len == 0) return 0;

    for (uint256 i = len; i != 0; --i) {
      CurveBreakpoint storage bp = _baselineCurve[i - 1];
      if (bp.lpFeeFloor <= lpFee) return bp.protocolFee;
    }
    return 0;
  }

  /// @dev Scales each 12-bit directional fee component by a basis-point multiplier,
  /// clamping each to MAX_PROTOCOL_FEE (1000). The two 12-bit components are extracted,
  /// scaled independently, and repacked into a single uint24.
  /// @param baseFee The base protocol fee (two 12-bit directional components packed).
  /// @param multiplierBps The multiplier in basis points (10000 = 1x, 5000 = 0.5x).
  /// @return The scaled and clamped protocol fee.
  function _applyMultiplier(uint24 baseFee, uint16 multiplierBps) internal pure returns (uint24) {
    uint256 fee0 = uint256(baseFee & 0xFFF) * multiplierBps / 10_000;
    uint256 fee1 = uint256(baseFee >> 12) * multiplierBps / 10_000;
    if (fee0 > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) fee0 = ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
    if (fee1 > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) fee1 = ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
    return uint24((fee1 << 12) | fee0);
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
