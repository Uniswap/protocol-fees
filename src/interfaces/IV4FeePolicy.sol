// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

/// @dev A breakpoint in the baseline curve. Protocol fee is applied for pools whose LP fee
/// is >= lpFeeFloor. Breakpoints must be stored in ascending order of lpFeeFloor.
struct CurveBreakpoint {
  /// @dev The minimum LP fee (in pips) for this breakpoint to apply. Pools with an LP fee
  /// >= this value and < the next breakpoint's floor receive this breakpoint's protocolFee.
  uint24 lpFeeFloor;
  /// @dev The protocol fee to apply. Packed as two 12-bit directional components:
  /// lower 12 bits = 0→1 fee, upper 12 bits = 1→0 fee. Each must be <= MAX_PROTOCOL_FEE.
  uint24 protocolFee;
}

/// @title IV4FeePolicy
/// @notice Interface for the V4 fee policy contract that computes protocol fees based on
/// automated hook classification and governance-configured parameters.
/// @dev Hook family IDs are governance-assigned uint8 values (1-255). 0 = unclassified.
/// Family IDs have no hardcoded semantic meaning — labels live in offchain documentation.
/// Static NativeMath pools bypass classification and use the baseline curve directly.
/// Custom-accounting hooks and dynamic fee pools require a governance-assigned familyId.
/// @custom:security-contact security@uniswap.org
interface IV4FeePolicy {
  // --- Errors ---

  /// @notice Thrown when an unauthorized address calls a restricted function.
  error Unauthorized();

  /// @notice Thrown when a fee value fails ProtocolFeeLibrary.isValidProtocolFee.
  error InvalidFeeValue();

  /// @notice Thrown when familyId == 0 is passed to a function that requires > 0.
  error InvalidFamilyId();

  /// @notice Thrown when setBaselineCurve is called with an empty array.
  error EmptyCurve();

  /// @notice Thrown when baseline curve breakpoints are not in strictly ascending order.
  error CurveNotAscending();

  /// @notice Thrown when currency0 >= currency1 in setPairFee.
  error CurrenciesOutOfOrder();

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
  /// @param familyId The family whose default was changed.
  /// @param feeValue The new default fee (0 = removed).
  event FamilyDefaultUpdated(uint8 indexed familyId, uint24 feeValue);

  /// @notice Emitted when a family's multiplier is updated.
  /// @param familyId The family whose multiplier was changed.
  /// @param multiplierBps The new multiplier in basis points (0 = removed).
  event FamilyMultiplierUpdated(uint8 indexed familyId, uint16 multiplierBps);

  /// @notice Emitted when a pair fee is updated.
  /// @param pairHash The canonical hash of the token pair.
  /// @param feeValue The new pair fee (0 = removed).
  event PairFeeUpdated(bytes32 indexed pairHash, uint24 feeValue);

  /// @notice Emitted when the baseline curve is replaced.
  /// @param breakpointCount The number of breakpoints in the new curve.
  event BaselineCurveUpdated(uint256 breakpointCount);

  /// @notice Emitted when the default classified fee is updated.
  /// @param feeValue The new default fee (0 = removed).
  event DefaultFeeUpdated(uint24 feeValue);

  // --- Constants ---

  /// @notice Bitmask for the four RETURNS_DELTA flags (bits 0-3 of hook address).
  /// @dev BEFORE_SWAP_RETURNS_DELTA (bit 3) | AFTER_SWAP_RETURNS_DELTA (bit 2) |
  /// AFTER_ADD_LIQUIDITY_RETURNS_DELTA (bit 1) | AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA (bit 0)
  /// @return The bitmask value (0xF).
  function CUSTOM_ACCOUNTING_MASK() external pure returns (uint160);

  // --- Immutables ---

  /// @notice The Uniswap V4 PoolManager this policy reads state from.
  /// @return The PoolManager contract.
  function POOL_MANAGER() external view returns (IPoolManager);

  // --- State ---

  /// @notice The address authorized to configure fees.
  /// @return The current fee setter address.
  function feeSetter() external view returns (address);

  /// @notice Fallback fee for all classified pools when no family-specific config applies.
  /// @dev Also used for unclassified hooks (familyId == 0). Sentinel-encoded in storage.
  /// @return The sentinel-encoded default fee.
  function defaultFee() external view returns (uint24);

  /// @notice Returns the governance-assigned family ID for a hook.
  /// @dev 0 = unclassified. StaticNativeMath pools bypass this entirely.
  /// @param hook The hook address to query.
  /// @return The family ID (0-255).
  function hookFamilyId(address hook) external view returns (uint8);

  /// @notice Returns the default protocol fee for a given family ID.
  /// @param familyId The family to query.
  /// @return The sentinel-encoded default fee for the family.
  function familyDefaults(uint8 familyId) external view returns (uint24);

  /// @notice Returns the multiplier (basis points) for a given family ID.
  /// @dev 10000 = 1x, 5000 = 0.5x. Applied to pairFees to derive a scaled fee.
  /// @param familyId The family to query.
  /// @return The multiplier in basis points (0 = not set).
  function familyMultiplierBps(uint8 familyId) external view returns (uint16);

  /// @notice Returns the pair fee for a token pair hash.
  /// @dev Flat mapping — one fee per pair. StaticNativeMath uses it directly (overrides
  /// baseline curve). Classified pools scale it by the family multiplier.
  /// @param pairHash The canonical keccak256 hash of the sorted token pair.
  /// @return The sentinel-encoded pair fee (0 = not set).
  function pairFees(bytes32 pairHash) external view returns (uint24);

  /// @notice Returns the number of breakpoints in the baseline curve.
  /// @return The count of breakpoints.
  function baselineCurveLength() external view returns (uint256);

  /// @notice Returns the breakpoint at the given index.
  /// @param index The zero-based index into the curve array.
  /// @return lpFeeFloor The minimum LP fee for this breakpoint.
  /// @return protocolFee The protocol fee applied at this breakpoint.
  function baselineCurve(uint256 index)
    external
    view
    returns (uint24 lpFeeFloor, uint24 protocolFee);

  // --- Pure Classification ---

  /// @notice Returns true if the hook has any RETURNS_DELTA flag set (bits 0-3).
  /// @dev Pure function of the hook address — no storage reads, no external calls.
  /// @param hook The hook address to check.
  /// @return True if the hook performs custom accounting.
  function isCustomAccounting(address hook) external pure returns (bool);

  // --- Fee Computation ---

  /// @notice Computes the protocol fee for a pool.
  /// @dev Three paths:
  /// 1. StaticNativeMath (no return-delta flags, static fee): pair fee or baseline curve.
  /// 2. Dynamic fee NativeMath: requires governance familyId (Slot0.lpFee is unreliable).
  /// 3. CustomAccounting (return-delta flags set): requires governance familyId.
  /// Paths 2 and 3 fall through to defaultFee if unclassified.
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

  // --- Default Fee (onlyFeeSetter) ---

  /// @notice Sets the fallback fee for all classified pools (including unclassified hooks).
  /// @dev Setting 0 sets an explicit zero fee. Use clearDefaultFee to remove entirely.
  /// @param feeValue The protocol fee to set. Must pass isValidProtocolFee if non-zero.
  function setDefaultFee(uint24 feeValue) external;

  /// @notice Removes the default fee, so unclassified pools return 0.
  function clearDefaultFee() external;

  // --- Curve Configuration (onlyFeeSetter) ---

  /// @notice Replaces the entire baseline curve with new breakpoints.
  /// @dev Breakpoints must be in strictly ascending order of lpFeeFloor. At least one
  /// required. Each breakpoint's protocolFee must pass isValidProtocolFee.
  /// @param breakpoints The new curve breakpoints, sorted ascending by lpFeeFloor.
  function setBaselineCurve(CurveBreakpoint[] calldata breakpoints) external;

  // --- Family Defaults & Multipliers (onlyFeeSetter) ---

  /// @notice Sets the default protocol fee for a given family ID.
  /// @dev familyId must be > 0. Setting 0 sets explicit zero. Use clearFamilyDefault to
  /// remove entirely.
  /// @param familyId The family to configure.
  /// @param feeValue The default fee. Must pass isValidProtocolFee if non-zero.
  function setFamilyDefault(uint8 familyId, uint24 feeValue) external;

  /// @notice Removes the default fee for a family, falling through in the waterfall.
  /// @param familyId The family to clear.
  function clearFamilyDefault(uint8 familyId) external;

  /// @notice Sets a multiplier for a family, applied to pairFees.
  /// @dev familyId must be > 0. multiplierBps in basis points (10000 = 1x).
  /// The scaled fee is clamped so each 12-bit component <= MAX_PROTOCOL_FEE.
  /// @param familyId The family to configure.
  /// @param multiplierBps The multiplier in basis points.
  function setFamilyMultiplier(uint8 familyId, uint16 multiplierBps) external;

  /// @notice Removes the multiplier for a family.
  /// @param familyId The family to clear.
  function clearFamilyMultiplier(uint8 familyId) external;

  // --- Pair Fees (onlyFeeSetter) ---

  /// @notice Sets the pair fee for a token pair.
  /// @dev StaticNativeMath pools use this directly (overrides baseline curve). Classified
  /// pools scale it by familyMultiplierBps. Setting 0 sets explicit zero.
  /// Use clearPairFee to remove entirely.
  /// @param currency0 The lower currency of the pair (must be < currency1).
  /// @param currency1 The higher currency of the pair.
  /// @param feeValue The pair fee. Must pass isValidProtocolFee if non-zero.
  function setPairFee(Currency currency0, Currency currency1, uint24 feeValue) external;

  /// @notice Removes the pair fee, falling through to the baseline curve.
  /// @param currency0 The lower currency of the pair (must be < currency1).
  /// @param currency1 The higher currency of the pair.
  function clearPairFee(Currency currency0, Currency currency1) external;
}
