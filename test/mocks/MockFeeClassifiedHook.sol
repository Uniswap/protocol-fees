// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {IFeeClassifiedHook} from "../../src/interfaces/IFeeClassifiedHook.sol";

/// @notice Mock hook that self-reports behavioral flags via IFeeClassifiedHook.
contract MockFeeClassifiedHook is IFeeClassifiedHook {
  uint256 public immutable flags;

  constructor(uint256 _flags) {
    flags = _flags;
  }

  function protocolFeeFlags() external view returns (uint256) {
    return flags;
  }
}

/// @notice Mock hook that wastes all gas on protocolFeeFlags() to test griefing protection.
contract GriefingHook is IFeeClassifiedHook {
  function protocolFeeFlags() external pure returns (uint256) {
    while (true) {}
    return 1; // unreachable
  }
}

/// @notice Mock hook that reverts on protocolFeeFlags().
contract RevertingHook {
  function protocolFeeFlags() external pure returns (uint256) {
    revert("not classified");
  }
}
