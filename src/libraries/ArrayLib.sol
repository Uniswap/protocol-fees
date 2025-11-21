// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ArrayLib
/// @notice A utility library for working with uint24 arrays
/// @dev Provides helper functions for common array operations on uint24[] storage arrays
library ArrayLib {
  /// @notice Checks if a value exists in a uint24 array
  /// @dev Performs a linear search through the array to find the value
  /// @param array The storage array to search through
  /// @param value The uint24 value to search for
  /// @return True if the value exists in the array, false otherwise
  function includes(uint24[] storage array, uint24 value) internal view returns (bool) {
    uint256 length = array.length;
    for (uint256 i; i < length; i++) {
      if (array[i] == value) return true;
    }
    return false;
  }
}
