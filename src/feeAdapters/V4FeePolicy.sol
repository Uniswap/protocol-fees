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
contract V4FeePolicy is IV4FeePolicy, Owned {
  using LPFeeLibrary for uint24;

  /// @dev Bitmask for the four RETURNS_DELTA flags (bits 0-3 of hook address).
  uint160 public constant CUSTOM_ACCOUNTING_MASK = 0xF;

  /// @notice Sentinel address that assigns a ruleset to native math hooked pools.
  address public constant NATIVE_MATH_POOL_SENTINEL = address(1);

  /// @notice Registered rulesets per hook. `address(0)` assigns a ruleset to hookless pools.
  mapping(address hook => IV4ProtocolFeeRuleset) public rulesets;

  uint24 public defaultFee;

  /// @notice The address that can set protocol fee rulesets.
  address public feeSetter;

  constructor(address owner, address _feeSetter) Owned(owner) {
    feeSetter = _feeSetter;
  }

  /// @notice Restricts access to the fee setter address.
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

  /// @dev Internal function to set a protocol fee ruleset for a given hook.
  function _setProtocolFeeRuleset(address hook, IV4ProtocolFeeRuleset ruleset) internal {
    emit ProtocolFeeRulesetChanged(hook, ruleset);
    rulesets[hook] = ruleset;
  }

  /// @notice Get the protocol fee from a ruleset, validating the fee before returning it.
  /// @dev Reverts to prevent calls to the zero address, which SHOULD be checked by the caller.
  /// @dev Calls to addresses which do not contain code or contracts that do not implement
  ///      the IV4ProtocolFeeRuleset interface are allowed as they will revert.
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

  /// @dev Validates protocol fee bounds.
  function _validateFee(uint24 feeValue) internal pure {
    if (!ProtocolFeeLibrary.isValidProtocolFee(feeValue)) revert InvalidFeeValue();
  }

  /// @dev Returns true if the hook address has any RETURNS_DELTA flag set (bits 0-3).
  function _isCustomAccounting(address hook) internal pure returns (bool) {
    return uint160(hook) & CUSTOM_ACCOUNTING_MASK != 0;
  }
}
