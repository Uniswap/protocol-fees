// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {
  IAggregatorHookProtocolFees
} from "../../src/interfaces/external/IAggregatorHookProtocolFees.sol";

/// @notice A mock of the protocol fee multiplier getter of an aggregator hook.
contract MockAggregatorHook is IAggregatorHookProtocolFees {
  uint24 public immutable protocolFeeMultiplier;

  constructor(uint24 multiplier) {
    protocolFeeMultiplier = multiplier;
  }
}
