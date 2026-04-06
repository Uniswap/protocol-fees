// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {IFeeClassifiedHook} from "../../src/interfaces/IFeeClassifiedHook.sol";

/// @notice Mock hook that self-reports its protocol fee family via IFeeClassifiedHook.
contract MockFeeClassifiedHook is IFeeClassifiedHook {
  uint8 public immutable familyId;

  constructor(uint8 _familyId) {
    familyId = _familyId;
  }

  function protocolFeeFamily() external view returns (uint8) {
    return familyId;
  }
}

/// @notice Mock hook that wastes all gas on protocolFeeFamily() to test griefing protection.
contract GriefingHook is IFeeClassifiedHook {
  function protocolFeeFamily() external pure returns (uint8) {
    while (true) {} // infinite loop — will consume all gas
    return 1; // unreachable
  }
}

/// @notice Mock hook that reverts on protocolFeeFamily().
contract RevertingHook {
  function protocolFeeFamily() external pure returns (uint8) {
    revert("not classified");
  }
}
