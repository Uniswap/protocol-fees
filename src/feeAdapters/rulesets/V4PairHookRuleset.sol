// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IV4FeePolicy, IV4ProtocolFeeRuleset} from "../../interfaces/IV4FeePolicy.sol";
import {IV4PairHookRuleset} from "../../interfaces/IV4PairHookRuleset.sol";
import {IV4StaticCurveRuleset} from "../../interfaces/IV4StaticCurveRuleset.sol";

/// @title V4PairHookRuleset
/// @notice The base of the rulesets for dynamic-fee pair hooks. It returns the fee of the hookless
/// curve for an LP fee from the hook's configuration of the pool.
/// @custom:security-contact security@uniswap.org
abstract contract V4PairHookRuleset is IV4PairHookRuleset {
  /// @dev The key of hookless pools in the rulesets of the policy.
  address internal constant NO_HOOK = address(0);

  /// @inheritdoc IV4PairHookRuleset
  IV4FeePolicy public immutable POLICY;

  /// @param policy The policy on which the ruleset looks up the hookless curve.
  constructor(IV4FeePolicy policy) {
    if (address(policy) == address(0)) revert AddressCannotBeZero();
    POLICY = policy;
  }

  /// @inheritdoc IV4ProtocolFeeRuleset
  /// @dev Reverts if no ruleset is set for hookless pools, or if that ruleset is not a static
  /// curve.
  function getProtocolFee(PoolKey calldata key) external view returns (uint24) {
    IV4ProtocolFeeRuleset curve = POLICY.rulesets(NO_HOOK);
    if (address(curve) == address(0)) revert HooklessCurveNotSet();
    return IV4StaticCurveRuleset(address(curve)).getFeeForLpFee(_lpFee(key));
  }

  /// @inheritdoc IV4PairHookRuleset
  function lpFee(PoolKey calldata key) external view returns (uint24) {
    return _lpFee(key);
  }

  /// @dev Returns the LP fee from the hook's configuration of the pool, in pips.
  function _lpFee(PoolKey calldata key) internal view virtual returns (uint24);
}
