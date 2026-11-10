// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "solmate/src/auth/Owned.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {
  IV4FeePolicy,
  ProtocolFeeRulesetAssignment,
  IV4ProtocolFeeRuleset
} from "../interfaces/IV4FeePolicy.sol";
import {
  ERC165Checker
} from "openzeppelin-contracts/contracts/utils/introspection/ERC165Checker.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";

/// @title V4FeePolicy
/// @notice Gives the protocol fee of a Uniswap v4 pool to V4FeeAdapter. The fee comes from the
/// first of these that applies: the ruleset of the hook (or of hookless pools), the ruleset of
/// native math hooked pools, a ruleset that the hook declares, and the default fee.
/// @dev The owner sets the fee setter. The fee setter sets the rulesets and the default fee.
/// @custom:security-contact security@uniswap.org
contract V4FeePolicy is IV4FeePolicy, Owned {
  using LPFeeLibrary for uint24;

  /// @dev Mask for the four RETURNS_DELTA flags (bits 0-3 of the hook address).
  uint160 public constant CUSTOM_ACCOUNTING_MASK = 0xF;

  /// @notice Sentinel address that assigns a ruleset to native math hooked pools.
  address public constant NATIVE_MATH_POOL_SENTINEL = address(1);

  /// @notice Registered rulesets per hook. `address(0)` assigns a ruleset to hookless pools.
  mapping(address hook => IV4ProtocolFeeRuleset) public rulesets;

  /// @notice The protocol fee of a pool that no ruleset applies to.
  uint24 public defaultFee;

  /// @notice The address that can set protocol fee rulesets.
  address public feeSetter;

  /// @param owner The owner. The owner can set the fee setter.
  /// @param _feeSetter The fee setter. The fee setter can set the rulesets and the default fee.
  constructor(address owner, address _feeSetter) Owned(owner) {
    feeSetter = _feeSetter;
  }

  /// @notice Reverts if the caller is not the fee setter.
  modifier onlyFeeSetter() {
    if (msg.sender != feeSetter) revert Unauthorized();
    _;
  }

  /// @inheritdoc IV4FeePolicy
  function computeFee(PoolKey calldata key) public view returns (uint24) {
    address hook = address(key.hooks);
    IV4ProtocolFeeRuleset ruleset = rulesets[hook];

    // If a ruleset is set for the hook address (including hookless), return its fee.
    if (address(ruleset) != address(0)) return _handleGetProtocolFee(ruleset, key);
    // If hookless pools have no ruleset, fallback to defaultFee.
    if (hook == address(0)) return defaultFee;

    // Native math hooked pools (aka pools with a hook, static LP fee, and no delta returning flags)
    if (!_isCustomAccounting(hook) && !key.fee.isDynamicFee()) {
      IV4ProtocolFeeRuleset nativeMathRuleset = rulesets[NATIVE_MATH_POOL_SENTINEL];
      if (address(nativeMathRuleset) != address(0)) {
        return _handleGetProtocolFee(nativeMathRuleset, key);
      }
    }

    // If the hook declares its own ruleset, return the fee from the hook.
    if (ERC165Checker.supportsInterface(hook, type(IV4ProtocolFeeRuleset).interfaceId)) {
      return _handleGetProtocolFee(IV4ProtocolFeeRuleset(hook), key);
    }

    // Fallback to the default fee.
    return defaultFee;
  }

  /// @inheritdoc IV4FeePolicy
  function setProtocolFeeRuleset(address hook, IV4ProtocolFeeRuleset ruleset)
    external
    onlyFeeSetter
  {
    _setProtocolFeeRuleset(hook, ruleset);
  }

  /// @inheritdoc IV4FeePolicy
  function batchSetProtocolFeeRulesets(ProtocolFeeRulesetAssignment[] calldata assignments)
    external
    onlyFeeSetter
  {
    uint256 len = assignments.length;
    for (uint256 i; i < len; ++i) {
      ProtocolFeeRulesetAssignment calldata a = assignments[i];
      _setProtocolFeeRuleset(a.hook, a.ruleset);
    }
  }

  /// @inheritdoc IV4FeePolicy
  function setFeeSetter(address newFeeSetter) external onlyOwner {
    emit FeeSetterUpdated(feeSetter, newFeeSetter);
    feeSetter = newFeeSetter;
  }

  /// @inheritdoc IV4FeePolicy
  function setDefaultFee(uint24 _defaultFee) external onlyFeeSetter {
    _validateFee(_defaultFee);
    emit DefaultFeeUpdated(defaultFee, _defaultFee);
    defaultFee = _defaultFee;
  }

  /// @dev Sets the ruleset of a hook.
  /// @param hook The hook address, or a sentinel key.
  /// @param ruleset The ruleset of the hook. The zero address removes the ruleset of the hook.
  function _setProtocolFeeRuleset(address hook, IV4ProtocolFeeRuleset ruleset) internal {
    emit ProtocolFeeRulesetChanged(hook, ruleset);
    rulesets[hook] = ruleset;
  }

  /// @notice Returns the protocol fee from a ruleset. Reverts if the fee is above MAX_PROTOCOL_FEE.
  /// @dev Reverts if the ruleset is the zero address. The caller must not pass the zero address.
  /// @dev A call to an address without code, or to a contract that does not implement
  ///      IV4ProtocolFeeRuleset, reverts.
  /// @param ruleset The ruleset.
  /// @param key The key of the pool.
  /// @return The protocol fee from the ruleset.
  function _handleGetProtocolFee(IV4ProtocolFeeRuleset ruleset, PoolKey calldata key)
    internal
    view
    returns (uint24)
  {
    if (address(ruleset) == address(0)) revert AddressCannotBeZero();
    uint24 fee = ruleset.getProtocolFee(key);
    _validateFee(fee);
    return fee;
  }

  /// @dev Reverts if the fee is above MAX_PROTOCOL_FEE.
  /// @param feeValue The protocol fee.
  function _validateFee(uint24 feeValue) internal pure {
    if (!ProtocolFeeLibrary.isValidProtocolFee(feeValue)) revert InvalidFeeValue();
  }

  /// @dev Returns true if the hook has a RETURNS_DELTA flag (bits 0-3).
  /// @param hook The hook address.
  /// @return True if the hook address has a RETURNS_DELTA flag.
  function _isCustomAccounting(address hook) internal pure returns (bool) {
    return uint160(hook) & CUSTOM_ACCOUNTING_MASK != 0;
  }
}
