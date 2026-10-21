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

  /// @dev Mask for the four RETURNS_DELTA flags (bits 0-3 of the hook address).
  uint160 public constant CUSTOM_ACCOUNTING_MASK = 0xF;

  /// @notice Sentinel addresses for pools that have no hook, and for the static curve.
  /// @dev The fee setter can set a ruleset at these addresses.
  address public constant HOOKLESS_POLICY_SENTINEL = address(0);
  address public constant STATIC_CURVE_POLICY_SENTINEL = address(1);
  /// @notice The zero fee.
  uint24 public constant ZERO_FEE = 0;

  /// @notice The ruleset of each hook.
  mapping(address hook => IV4ProtocolFeeRuleset) public rulesets;

  uint24 public defaultFee;

  /// @notice The address that can set protocol fee rulesets.
  address public feeSetter;

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
    IV4ProtocolFeeRuleset ruleset = rulesets[address(key.hooks)];

    // If a ruleset is set for the hook, return the fee from that ruleset.
    if (address(ruleset) != address(0)) return _handleGetProtocolFee(ruleset, key);
    // Hookless pools use the address(0) policy if set, else defaultFee.
    if (address(key.hooks) == address(0)) return defaultFee;

    // Static-fee hooked pools use the curve at STATIC_CURVE_POLICY_SENTINEL when it is set.
    // An unset curve falls through to hook opt-in, then defaultFee.
    if (!_isCustomAccounting(address(key.hooks)) && !key.fee.isDynamicFee()) {
      IV4ProtocolFeeRuleset staticCurveRuleset = rulesets[STATIC_CURVE_POLICY_SENTINEL];
      if (address(staticCurveRuleset) != address(0)) {
        return _handleGetProtocolFee(staticCurveRuleset, key);
      }
    }
    // If the hook supports the ruleset interface, return the fee from the hook.
    if (ERC165Checker.supportsInterface(
        address(key.hooks), type(IV4ProtocolFeeRuleset).interfaceId
      )) return _handleGetProtocolFee(IV4ProtocolFeeRuleset(address(key.hooks)), key);
    // Return the default fee.
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
  function _setProtocolFeeRuleset(address hook, IV4ProtocolFeeRuleset ruleset) internal {
    emit ProtocolFeeRulesetChanged(hook, ruleset);
    rulesets[hook] = ruleset;
  }

  /// @notice Returns the protocol fee from a ruleset. Reverts if the fee is above MAX_PROTOCOL_FEE.
  /// @dev Reverts if the ruleset is the zero address. The caller must not pass the zero address.
  /// @dev A call to an address without code, or to a contract that does not implement
  ///      IV4ProtocolFeeRuleset, reverts.
  function _handleGetProtocolFee(IV4ProtocolFeeRuleset policy, PoolKey calldata key)
    internal
    view
    returns (uint24)
  {
    if (address(policy) == address(0)) revert AddressCannotBeZero();
    uint24 fee = policy.getProtocolFee(key);
    _validateFee(fee);
    return fee;
  }

  /// @dev Reverts if the fee is above MAX_PROTOCOL_FEE.
  function _validateFee(uint24 feeValue) internal pure {
    if (!ProtocolFeeLibrary.isValidProtocolFee(feeValue)) revert InvalidFeeValue();
  }

  /// @dev Returns true if the hook has a RETURNS_DELTA flag (bits 0-3).
  function _isCustomAccounting(address hook) internal pure returns (bool) {
    return uint160(hook) & CUSTOM_ACCOUNTING_MASK != 0;
  }
}
