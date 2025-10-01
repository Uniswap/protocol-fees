// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IUNI Interface
/// @notice Interface for the UNI token contract extending ERC20 functionality
/// @dev This interface extends IERC20 with UNI-specific minting and governance functions
interface IUNI is IERC20 {
  /// @notice Returns the address that has minting privileges for UNI tokens
  /// @return The address of the current minter
  function minter() external view returns (address);

  /// @notice Returns the timestamp after which minting is allowed
  /// @return The timestamp after which the next mint is allowed
  function mintingAllowedAfter() external view returns (uint256);

  /// @notice Mints new UNI tokens to a specified address
  /// @dev Only callable by the designated minter
  /// @param dst The address to receive the newly minted tokens
  /// @param rawAmount The amount of tokens to mint (in wei)
  function mint(address dst, uint256 rawAmount) external;

  /// @notice Sets a new minter address
  /// @dev Only callable by the current minter, permanently transfers minting rights
  /// @param minter The address of the new minter
  function setMinter(address minter) external;

  /// @notice Returns the minimum time that must elapse between minting operations
  /// @dev Used to enforce a delay between token minting
  /// @return The minimum time between mints in seconds
  function minimumTimeBetweenMints() external view returns (uint32);
}
