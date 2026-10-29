// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IV4FeePolicy, IV4ProtocolFeeRuleset} from "../../interfaces/IV4FeePolicy.sol";
import {IV4PairHookRuleset} from "../../interfaces/IV4PairHookRuleset.sol";

/// @title V4PairHookRuleset
/// @notice The base of the rulesets for dynamic-fee pair hooks. It returns the fee that the policy
/// gives a hookless pool with the same currencies and tick spacing, and an LP fee from the hook's
/// configuration of the pool.
/// @custom:security-contact security@uniswap.org
abstract contract V4PairHookRuleset is IV4PairHookRuleset {
  /// @inheritdoc IV4PairHookRuleset
  IV4FeePolicy public immutable POLICY;

  /// @param policy The policy that gives the fee of hookless pools.
  constructor(IV4FeePolicy policy) {
    if (address(policy) == address(0)) revert AddressCannotBeZero();
    POLICY = policy;
  }

  /// @inheritdoc IV4ProtocolFeeRuleset
  function getProtocolFee(PoolKey calldata key) external view returns (uint24) {
    return POLICY.computeFee(
      PoolKey({
        currency0: key.currency0,
        currency1: key.currency1,
        fee: _lpFee(key),
        tickSpacing: key.tickSpacing,
        hooks: IHooks(address(0))
      })
    );
  }

  /// @inheritdoc IV4PairHookRuleset
  function lpFee(PoolKey calldata key) external view returns (uint24) {
    return _lpFee(key);
  }

  /// @dev Returns the LP fee from the hook's configuration of the pool, in pips.
  function _lpFee(PoolKey calldata key) internal view virtual returns (uint24);
}
