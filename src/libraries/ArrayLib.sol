// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library ArrayLib {
  function includes(uint24[] storage array, uint24 value) internal view returns (bool) {
    for (uint256 i = 0; i < array.length; i++) {
      if (array[i] == value) return true;
    }
    return false;
  }
}
