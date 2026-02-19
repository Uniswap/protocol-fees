// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";

/// @title IFeeDripper
interface IFeeDripper {
  event DripStarted(
    address indexed currency, uint48 indexed fullyReleasedBlock, uint160 perBlockRate
  );
  event Released(address indexed currency, uint256 amount);
  event ReleaseWindowSet(uint16 indexed releaseWindow);

  /// @notice Thrown when the supplied release window is zero.
  error InvalidReleaseWindow();
  /// @notice Thrown when the drip amount is bigger than uint160.max.
  error DripAmountTooLarge(uint256 amount, uint256 max);
  /// @notice Thrown when the token jar address provided in the constructor is zero address.
  error InvalidTokenJar();

  /// @notice Syncs new deposits and resets the release window. Accrued tokens are released first,
  ///   then the entire remaining balance (old unreleased + new deposits) is spread over a fresh
  ///   releaseWindow.
  /// @dev Known griefing vector: anyone can send a small amount (>= releaseWindow wei) to this
  ///   contract and call drip() to reset the release window, slowing the flow to TOKEN_JAR. This is
  ///   accepted because slowing flow in the same direction as FeeDripper's purpose (preventing
  ///   TokenJar overflow).
  /// @param currency The currency to drip
  function drip(Currency currency) external;

  /// @notice Releases accrued tokens and updates the latest release block.
  /// @dev This will not start a drip for any idle tokens in the contract.
  /// @param currency The currency to release
  function release(Currency currency) external;

  /// @notice Sets the release window.
  /// @dev Only callable by the owner.
  /// @param _releaseWindow The new release window
  function setReleaseWindow(uint16 _releaseWindow) external;
}
