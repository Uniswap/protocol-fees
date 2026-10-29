// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice The protocol fee multiplier getter of an aggregator hook.
/// @dev A subset of `ProtocolFees` in Uniswap/v4-hooks-public at commit 82de6aa
/// (`src/aggregator-hooks/ProtocolFees.sol`), which BaseAggregatorHook inherits.
interface IAggregatorHookProtocolFees {
  /// @notice The multiplier that the hook applies to the protocol fee of its pool. The hook
  /// charges the protocol fee times this multiplier on each swap.
  function protocolFeeMultiplier() external view returns (uint24);
}
