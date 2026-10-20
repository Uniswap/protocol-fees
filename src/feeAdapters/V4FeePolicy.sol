// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "solmate/src/auth/Owned.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {
  IV4FeePolicy,
  ProtocolFeeRulesetAssignment,
  IV4ProtocolFeeRuleset
} from "../interfaces/IV4FeePolicy.sol";
import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {ERC165Checker} from "openzeppelin-contracts/contracts/utils/introspection/ERC165Checker.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";

/// @title V4FeePolicy
contract V4FeePolicy is IV4FeePolicy, Owned {
  using LPFeeLibrary for uint24;

  /// @dev Bitmask for the four RETURNS_DELTA flags (bits 0-3 of hook address).
  uint160 public constant CUSTOM_ACCOUNTING_MASK = 0xF;

  /// @notice Sentinel addresses for hookless and static curve policies.
  /// @dev These MAY be overwritten by the fee setter.
  address public constant HOOKLESS_POLICY_SENTINEL = address(0);
  address public constant STATIC_CURVE_POLICY_SENTINEL = address(1);
  /// @notice The zero fee.
  uint24 public constant ZERO_FEE = 0;

  /// @notice Registered rulesets per hook.
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
    IV4ProtocolFeeRuleset ruleset = rulesets[address(key.hooks)];

    // If a policy is explictly set, return the protocol fee as reported
    if (address(ruleset) != address(0)) return _handleGetProtocolFee(ruleset, key);
    // Hookless pools cannot opt in. An unset hookless policy returns zero, not the default fee.
    if (address(key.hooks) == address(0)) return ZERO_FEE;

    // For hooked pools without custom accounting or dynamic fees, return the static fee curve
    // policy if set. An unset static curve falls through to the hook opt-in check.
    if (!_isCustomAccounting(address(key.hooks)) && !key.fee.isDynamicFee()) {
        IV4ProtocolFeeRuleset staticCurveRuleset = rulesets[STATIC_CURVE_POLICY_SENTINEL];
        if (address(staticCurveRuleset) != address(0)) {
            return _handleGetProtocolFee(staticCurveRuleset, key);
        }
    }
    // For hooks that return a protocol fee themselves, fetch it from the hook
    if (ERC165Checker.supportsInterface(address(key.hooks), type(IV4ProtocolFeeRuleset).interfaceId)) {
        return _handleGetProtocolFee(IV4ProtocolFeeRuleset(address(key.hooks)), key);
    }
    // Finally, return the default fee if set
    return defaultFee;
  }

  /// @inheritdoc IV4FeePolicy
  function setProtocolFeeRuleset(address hook, IV4ProtocolFeeRuleset ruleset) external onlyFeeSetter {
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
  function setDefaultFee(uint24 _defaultFee) external onlyFeeSetter() {
    _validateFee(_defaultFee);
    emit DefaultFeeUpdated(defaultFee, _defaultFee);
    defaultFee = _defaultFee;
  }

  /// @dev Internal function to set a protocol fee policy for a given hook.
  function _setProtocolFeeRuleset(address hook, IV4ProtocolFeeRuleset ruleset) internal {
    emit ProtocolFeeRulesetChanged(hook, ruleset);
    rulesets[hook] = ruleset;
  }

  /// @notice Get the protocol fee from a policy, validating the fee before returning it.
  /// @dev Reverts to prevent calls to the zero address, which SHOULD be checked by the caller.
  /// @dev Calls to addresses which do not contain code or contracts that do not implement
  ///      the IV4ProtocolFeeRuleset interface are allowed as they will revert.
  function _handleGetProtocolFee(IV4ProtocolFeeRuleset policy, PoolKey calldata key) internal view returns (uint24) {
    if(address(policy) == address(0)) revert AddressCannotBeZero();
    uint24 fee = policy.getProtocolFee(key);
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
