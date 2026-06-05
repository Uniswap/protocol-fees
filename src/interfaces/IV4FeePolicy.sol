// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

/// @dev A single segment of the piecewise-linear protocol-fee schedule on the
/// StaticNativeMath path. Buckets are stored in an ascending-by-lpFeeFloor array.
/// For a given `key.fee`, evaluation finds the bucket with the largest floor
/// <= key.fee (or bucket 0 if key.fee < floor_0) and returns
/// alpha + beta * (key.fee - floor) / 1_000_000 per direction (clamped to
/// MAX_PROTOCOL_FEE).
struct FeeBucket {
  /// @dev LP-fee floor for this bucket, in pips. Ascending across the array; matches v4-core fee
  /// type.
  uint24 lpFeeFloor;
  /// @dev Flat base fee per direction in pips. Must be <= MAX_PROTOCOL_FEE (1000).
  uint24 alphaPips;
  /// @dev Slope: pips of protocol fee per pip of (lpFee - floor). Capped to 1_000_000_000
  /// (above which any 1-pip delta saturates the per-direction MAX_PROTOCOL_FEE clamp).
  uint32 betaPips;
}

/// @dev A flag-to-family mapping rule. The policy walks rules in order; the first rule
/// whose requiredFlags are all present in the hook's self-reported flags wins.
struct FlagRule {
  /// @dev Bitmask of flags that must ALL be set in the hook's protocolFeeFlags() return
  /// value for this rule to match. The bits are an opaque convention between governance
  /// and hooks; see the governance guide for the values in active use.
  uint256 requiredFlags;
  /// @dev The family ID assigned when this rule matches. Must be > 0.
  uint8 familyId;
}

/// @dev Hook address and family for `batchSetHookFamily`.
struct HookFamilyAssignment {
  address hook;
  uint8 familyId;
}

/// @dev Token pair, family slot, and fee for `batchSetPairClassFee`.
struct PairClassFeeAssignment {
  Currency currency0;
  Currency currency1;
  uint8 familyId;
  uint24 feeValue;
}

/// @dev Token pair and family slot for `batchClearPairClassFee`.
struct PairClassFeeClear {
  Currency currency0;
  Currency currency1;
  uint8 familyId;
}

/// @title IV4FeePolicy
/// @notice Interface for the V4 fee policy contract that computes protocol fees based on
/// automated hook classification and governance-configured parameters.
/// @dev Governance hook family IDs are 1-255. 0 = unclassified. `NATIVE_MATH_FAMILY_ID`
/// (255) is also used internally for native-math resolution on static pools; governance may
/// reuse 255 for classified config when appropriate.
/// Hooks can self-report behavioral flags via IFeeClassifiedHook.protocolFeeFlags();
/// governance-configured flag rules map flag patterns to families automatically.
/// Static NativeMath pools bypass hook classification and derive their protocol fee from
/// `pairClassFees[pair][NATIVE_MATH_FAMILY_ID]` or a piecewise-linear fee-bucket schedule.
/// Custom-accounting hooks and dynamic fee pools require classification (governance
/// override, flag rule match, or defaultFee fallback).
/// @custom:security-contact security@uniswap.org
interface IV4FeePolicy {
  // --- Errors ---

  /// @notice Thrown when an unauthorized address calls a restricted function.
  error Unauthorized();

  /// @notice Thrown when a fee value fails ProtocolFeeLibrary.isValidProtocolFee.
  error InvalidFeeValue();

  /// @notice Thrown when familyId is 0 or `NATIVE_MATH_FAMILY_ID` on family-default setters.
  error InvalidFamilyId();

  /// @notice Thrown when a fee bucket's `betaPips` exceeds 1_000_000_000.
  error MultiplierTooLarge();

  /// @notice Thrown when currency0 >= currency1 in setPairClassFee.
  error CurrenciesOutOfOrder();

  /// @notice Thrown when a flag rule has requiredFlags == 0 or a non-governance familyId.
  error InvalidFlagRule();

  /// @notice Thrown when flag rules exceed the maximum allowed count.
  error TooManyFlagRules();

  /// @notice Thrown when flag rules are not sorted from most to least specific.
  error FlagRulesNotSorted();

  /// @notice Thrown when setFeeBuckets is called with an empty array.
  error EmptyBuckets();

  /// @notice Thrown when fee buckets are not in strictly ascending order of lpFeeFloor.
  error BucketsNotAscending();

  /// @notice Thrown when fee buckets exceed the maximum allowed count.
  error TooManyBuckets();

  // --- Events ---

  /// @notice Emitted when the fee setter address is updated.
  /// @param oldFeeSetter The previous fee setter address.
  /// @param newFeeSetter The new fee setter address.
  event FeeSetterUpdated(address indexed oldFeeSetter, address indexed newFeeSetter);

  /// @notice Emitted when a hook's family classification is set or cleared.
  /// @param hook The hook address that was classified.
  /// @param familyId The assigned family ID (0 = unclassified).
  event HookFamilySet(address indexed hook, uint8 familyId);

  /// @notice Emitted when a family's default protocol fee is updated.
  /// @dev `feeValue` is the encoded storage value: 0 = removed/unset,
  /// ZERO_FEE_SENTINEL = explicit zero fee.
  /// @param familyId The family whose default was changed.
  /// @param feeValue The new encoded default fee.
  event FamilyDefaultUpdated(uint8 indexed familyId, uint24 feeValue);

  /// @notice Emitted when a pair class fee is updated.
  /// @dev `feeValue` is the encoded storage value: 0 = removed/unset,
  /// ZERO_FEE_SENTINEL = explicit zero fee. `familyId` is `NATIVE_MATH_FAMILY_ID` for
  /// native-math pair overrides, or a governance family ID (1-255) otherwise.
  /// @param pairHash The canonical hash of the token pair.
  /// @param familyId The family slot that was changed.
  /// @param feeValue The new encoded fee.
  event PairClassFeeUpdated(bytes32 indexed pairHash, uint8 indexed familyId, uint24 feeValue);

  /// @notice Emitted when the fee buckets array is replaced.
  /// @param bucketCount The number of buckets in the new array.
  event FeeBucketsUpdated(uint256 bucketCount);

  /// @notice Emitted when the default classified fee is updated.
  /// @dev `feeValue` is the encoded storage value: 0 = removed/unset,
  /// ZERO_FEE_SENTINEL = explicit zero fee.
  /// @param feeValue The new encoded default fee.
  event DefaultFeeUpdated(uint24 feeValue);

  /// @notice Emitted when the flag rules array is replaced.
  /// @param ruleCount The number of rules in the new array.
  event FlagRulesUpdated(uint256 ruleCount);

  // --- Constants ---

  /// @notice Bitmask for the four RETURNS_DELTA flags (bits 0-3 of hook address).
  /// @dev BEFORE_SWAP_RETURNS_DELTA (bit 3) | AFTER_SWAP_RETURNS_DELTA (bit 2) |
  /// AFTER_ADD_LIQUIDITY_RETURNS_DELTA (bit 1) | AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA (bit 0)
  /// @return The bitmask value (0xF).
  function CUSTOM_ACCOUNTING_MASK() external pure returns (uint160);

  /// @notice Reserved `pairClassFees` family slot for native-math pair overrides.
  /// @dev Not assignable as a governance hook family. Distinct from `hookFamilyId == 0`.
  /// @return 0xFF (255 == `type(uint8).max`).
  function NATIVE_MATH_FAMILY_ID() external pure returns (uint8);

  /// @notice Reserved `pairClassFees` family slot for unclassified hooks.
  /// @dev Not assignable as a governance hook family. Distinct from `NATIVE_MATH_FAMILY_ID`.
  /// @return 0 (unclassified).
  function UNCLASSIFIED_FAMILY_ID() external pure returns (uint8);

  // --- Immutables ---

  /// @notice The Uniswap V4 PoolManager this policy reads state from.
  /// @return The PoolManager contract.
  function POOL_MANAGER() external view returns (IPoolManager);

  // --- State ---

  /// @notice The address authorized to configure fees.
  /// @return The current fee setter address.
  function feeSetter() external view returns (address);

  /// @notice Fallback fee for classified pools when no family-specific config applies.
  /// @dev Also used for unclassified hooks (familyId == 0). Sentinel-encoded in storage.
  /// @return The sentinel-encoded default fee.
  function defaultFee() external view returns (uint24);

  /// @notice Returns the governance-assigned family ID for a hook.
  /// @dev 0 = unclassified on the classified path. StaticNativeMath pools do not use this.
  /// @param hook The hook address to query.
  /// @return The family ID (0-255).
  function hookFamilyId(address hook) external view returns (uint8);

  /// @notice Returns the default protocol fee for a given family ID.
  /// @param familyId The family to query (must be > 0 when set via admin).
  /// @return The sentinel-encoded default fee for the family.
  function familyDefaults(uint8 familyId) external view returns (uint24);

  /// @notice Returns the pair class fee for a token pair and family slot.
  /// @dev `familyId == NATIVE_MATH_FAMILY_ID` is the StaticNativeMath pair override.
  /// Governance families use IDs 1-255; `NATIVE_MATH_FAMILY_ID` is the native-math slot.
  /// 0 in storage = not set.
  /// @param pairHash The canonical keccak256 hash of the sorted token pair.
  /// @param familyId The family slot to query.
  /// @return The sentinel-encoded fee (0 = not set).
  function pairClassFees(bytes32 pairHash, uint8 familyId) external view returns (uint24);

  /// @notice Returns the number of fee buckets configured.
  /// @return The count of fee buckets.
  function feeBucketsLength() external view returns (uint256);

  /// @notice Returns the fee bucket at the given index.
  /// @param index The zero-based index into the buckets array.
  /// @return lpFeeFloor The LP-fee floor for this bucket.
  /// @return alphaPips The flat base fee per direction in pips.
  /// @return betaPips The slope: pips of protocol fee per pip of (lpFee - floor).
  function feeBucket(uint256 index)
    external
    view
    returns (uint24 lpFeeFloor, uint24 alphaPips, uint32 betaPips);

  /// @notice Returns the number of flag rules configured.
  /// @return The count of flag rules.
  function flagRulesLength() external view returns (uint256);

  /// @notice Returns the flag rule at the given index.
  /// @param index The zero-based index into the rules array.
  /// @return requiredFlags The flags that must all be present for a match.
  /// @return familyId The family ID assigned on match.
  function flagRules(uint256 index) external view returns (uint256 requiredFlags, uint8 familyId);

  // --- Pure Classification ---

  /// @notice Returns true if the hook has any RETURNS_DELTA flag set (bits 0-3).
  /// @dev Pure function of the hook address — no storage reads, no external calls.
  /// @param hook The hook address to check.
  /// @return True if the hook performs custom accounting.
  function isCustomAccounting(address hook) external pure returns (bool);

  // --- Fee Computation ---

  /// @notice Computes the protocol fee for a pool.
  /// @dev Resolve family, then: native math (`NATIVE_MATH_FAMILY_ID` on static pools) →
  /// `pairClassFees[pair][family]` → `familyDefaults[family]` → `defaultFee`.
  /// Unclassified custom-accounting / dynamic-fee pools (`family == 0`) → `defaultFee` only.
  /// Callable by anyone (no access control) for offchain tooling.
  /// @param key The pool key to compute the fee for.
  /// @return fee The computed protocol fee (two 12-bit directional components packed).
  function computeFee(PoolKey calldata key) external view returns (uint24 fee);

  // --- Admin (onlyOwner) ---

  /// @notice Sets the fee setter address. Only callable by owner.
  /// @param newFeeSetter The new fee setter address.
  function setFeeSetter(address newFeeSetter) external;

  // --- Classification (onlyFeeSetter) ---

  /// @notice Assign a hook to a governance-defined family.
  /// @dev familyId 0 unclassifies the hook. Overwrites any existing classification.
  /// @param hook The hook address to classify.
  /// @param familyId The family ID to assign (0 = unclassify).
  function setHookFamily(address hook, uint8 familyId) external;

  /// @notice Assigns multiple hooks to families in one transaction.
  /// @param assignments Hook/family pairs. Emits `HookFamilySet` per entry.
  function batchSetHookFamily(HookFamilyAssignment[] calldata assignments) external;

  // --- Flag Rules (onlyFeeSetter) ---

  /// @notice Replaces the entire flag rules array atomically.
  /// @dev Rules are checked in order; the first rule whose requiredFlags are all present
  /// in the hook's self-reported flags wins. Rules must be sorted by non-increasing
  /// number of set bits in requiredFlags, so more specific patterns come first. Each
  /// rule must have requiredFlags != 0 and familyId > 0. Max 32 rules.
  /// @param rules The new flag rules, ordered by match priority (first match wins).
  function setFlagRules(FlagRule[] calldata rules) external;

  /// @notice Removes all flag rules.
  function clearFlagRules() external;

  // --- Default Fee (onlyFeeSetter) ---

  /// @notice Sets the fallback fee for classified pools (including unclassified hooks).
  /// @dev Setting 0 sets an explicit zero fee. Use clearDefaultFee to remove entirely.
  /// @param feeValue The protocol fee to set. Must pass isValidProtocolFee if non-zero.
  function setDefaultFee(uint24 feeValue) external;

  /// @notice Removes the default fee, so unclassified pools return 0.
  function clearDefaultFee() external;

  // --- Fee Bucket Configuration (onlyFeeSetter) ---

  /// @notice Replaces the entire fee-buckets array atomically.
  /// @dev Must be non-empty, ascending by `lpFeeFloor` (strict), and at most 16 buckets.
  /// Each bucket: `alphaPips <= MAX_PROTOCOL_FEE` (1000), `betaPips <= 1_000_000_000`.
  /// The lowest bucket's `alpha` acts as a minimum-fee floor for very-low-LP-fee pools
  /// because of the snap-to-lowest behavior in `computeFee`.
  /// Reverts: `EmptyBuckets`, `TooManyBuckets`, `BucketsNotAscending`,
  /// `InvalidFeeValue` (alpha out of range), `MultiplierTooLarge` (beta out of range).
  /// @param buckets The new fee buckets, ordered ascending by lpFeeFloor.
  function setFeeBuckets(FeeBucket[] calldata buckets) external;

  /// @notice Removes all fee buckets. StaticNativeMath returns 0 when no pair class fee is set.
  function clearFeeBuckets() external;

  // --- Family Defaults (onlyFeeSetter) ---

  /// @notice Sets the default protocol fee for a governance family (1-254).
  /// @dev Reverts for 0 and `NATIVE_MATH_FAMILY_ID` (use pair class fees / buckets for 255).
  /// Setting fee 0 sets explicit zero. Use clearFamilyDefault to remove entirely.
  /// @param familyId The family to configure.
  /// @param feeValue The default fee. Must pass isValidProtocolFee if non-zero.
  function setFamilyDefault(uint8 familyId, uint24 feeValue) external;

  /// @notice Removes the default fee for a governance family (1-254).
  /// @dev Reverts for 0 and `NATIVE_MATH_FAMILY_ID`.
  /// @param familyId The family to clear.
  function clearFamilyDefault(uint8 familyId) external;

  // --- Pair Class Fees (onlyFeeSetter) ---

  /// @notice Sets the pair class fee for a token pair and family slot.
  /// @dev Use `NATIVE_MATH_FAMILY_ID` for native-math pair overrides, or 1-255 for
  /// governance families. Setting fee 0 sets explicit zero and does not fall through.
  /// Use clearPairClassFee to remove entirely.
  /// @param currency0 The lower currency of the pair (must be < currency1).
  /// @param currency1 The higher currency of the pair.
  /// @param familyId The family slot (`NATIVE_MATH_FAMILY_ID` or 1-255).
  /// @param feeValue The protocol fee. Must pass isValidProtocolFee if non-zero.
  function setPairClassFee(Currency currency0, Currency currency1, uint8 familyId, uint24 feeValue)
    external;

  /// @notice Sets multiple pair class fees in one transaction.
  /// @param assignments Pair/family/fee tuples. Emits `PairClassFeeUpdated` per entry.
  function batchSetPairClassFee(PairClassFeeAssignment[] calldata assignments) external;

  /// @notice Removes the pair class fee for a family slot.
  /// @param currency0 The lower currency of the pair (must be < currency1).
  /// @param currency1 The higher currency of the pair.
  /// @param familyId The family slot to clear.
  function clearPairClassFee(Currency currency0, Currency currency1, uint8 familyId) external;

  /// @notice Clears multiple pair class fees in one transaction.
  /// @param clears Pair/family slots to remove. Emits `PairClassFeeUpdated` with fee 0 per entry.
  function batchClearPairClassFee(PairClassFeeClear[] calldata clears) external;
}
