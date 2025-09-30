// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library ArrayLib {
  function includes(uint24[] storage array, uint24 value) internal view returns (bool) {
    uint256 length = array.length;
    for (uint256 i; i < length; i++) {
      if (array[i] == value) return true;
    }
    return false;
  }
}
