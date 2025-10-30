// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IUNI} from "./IUNI.sol";

interface IUNIMinter {
  /// @notice Thrown when attempting to complete revocation before the delay period has elapsed, or
  /// when attempting to re-revoke a split that has already been adjusted.
  error InvalidRevocation();
  /// @notice Thrown when attempting to complete revocation for splits without a pending revocation
  error NotPendingRevocation();
  /// @notice Thrown when granting units would exceed the maximum allowed
  error InsufficientUnits();
  /// @notice Thrown when attempting to mint with no units configured to splits
  error NoUnits();
  /// @notice Thrown when minting before January 1, 2026 00:00 UTC
  error MintingNotStarted();

  /// @notice Structure to hold recipient split information
  /// @param recipient The address that will receive minted UNI tokens
  /// @param units The number of units allocated to this recipient (out of MAX_UNITS)
  /// @param revocationDelayDays The number of days notice required for a revocation of this split
  /// @param pendingRevocationTime The timestamp when revocation can be completed, or 0 if not
  /// pending
  /// @param adjustedForRevocation Whether the split units have already been adjusted
  /// for revocation
  struct Split {
    address recipient;
    uint16 units;
    uint16 revocationDelayDays;
    uint48 pendingRevocationTime;
    bool adjustedForRevocation;
  }

  /// @notice The UNI token contract address on mainnet
  function UNI() external view returns (IUNI);

  /// @notice Total number of currently allocated units via splits
  /// @dev Always less than or equal to MAX_UNITS
  function totalUnits() external view returns (uint16);

  /// @notice Access the Splits array by index
  /// @return Split unpacked: recipient, units, revocationDelayDays, pendingRevocationTime,
  /// adjustedForRevocation
  function splits(uint256 index) external view returns (address, uint16, uint16, uint48, bool);

  /// @notice Executes the annual mint and distributes tokens proportionally to split recipients
  /// @dev Can be called by anyone once per year. Mints based on allocated splits only, unallocated
  /// splits reduce inflation
  /// @dev The underlying UNI token contract reverts if called with > 2% of total supply
  //    or if < 365 days since the last
  function mint() external;

  /// @notice Grants a split of the UNI inflation to a recipient
  /// @dev Only callable by owner (UNI DAO). Reverts if total splits would exceed MAX_UNITS
  /// @param _recipient The address that will receive the minted UNI tokens
  /// @param _unit The number of splits to allocate (out of MAX_UNITS total)
  /// @param _revocationDelayDays The number of days notice required for a revocation of this split
  function grantSplit(address _recipient, uint16 _unit, uint16 _revocationDelayDays) external;

  /// @notice Initiates the revocation process for a recipient's split
  /// @dev Only callable by owner. Sets a timestamp after which revocation can be completed
  /// @param _index The index in the splits array of the allocation to revoke
  function initiateRevokeSplit(uint256 _index) external;

  /// @notice Completes or updates split revocation based on timing relative to next mint
  /// @dev Can be called by anyone to update a split based on its pending revocation timing:
  ///   - If revocation completes before next mint: split is entirely removed
  ///   - If revocation extends into next mint period: split units are reduced proportionally
  ///     to time remaining until revocation (e.g., 90 days into 365-day period = ~25% of units)
  ///   - revokeSplit must be called to update units for pending revocation
  /// @param _index The index in the splits array of the allocation to revoke or update
  function revokeSplit(uint256 _index) external;

  /// @notice Transfers the UNI minter role to a new address
  /// @dev Only callable by owner. This is a critical operation that permanently transfers
  ///      the ability to mint UNI tokens to the new address. Once transferred, this contract
  ///      will no longer be able to mint UNI tokens unless the role is transferred back.
  /// @param _minter The address of the new minter contract or EOA
  function setMinter(address _minter) external;
}
