// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

/// @title Owned Interface
/// @dev Interface for Solmate's Owned.sol contract
interface IOwned {
  /// @return owner of the contract
  function owner() external view returns (address);

  /// @notice Transfers ownership of the contract to a new address
  function transferOwnership(address newOwner) external;
}
