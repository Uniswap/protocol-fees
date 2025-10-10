// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IUNI} from "./IUNI.sol";

interface IUNIMinter {
  /// @notice Thrown when attempting to complete revocation before the delay period has elapsed, or
  /// when attempting to re-revoke a share that has already been adjusted.
  error InvalidRevocation();
  /// @notice Thrown when attempting to complete revocation for shares without a pending revocation
  error NotPendingRevocation();
  /// @notice Thrown when granting shares would exceed the maximum allowed
  error InsufficientShares();
  /// @notice Thrown when attempting to mint with no configured shares
  error NoShares();

  /// @notice Structure to hold recipient share information
  /// @param recipient The address that will receive minted UNI tokens
  /// @param amount The number of shares allocated to this recipient (out of MAX_SHARES)
  /// @param revocationDelayDays The number of days notice required for a revocation of this share
  /// @param pendingRevocationTime The timestamp when revocation can be completed, or 0 if not
  /// pending
  /// @param adjustedForRevocation Whether the share amounts have already been adjusted
  /// for revocation
  struct Share {
    address recipient;
    uint16 amount;
    uint16 revocationDelayDays;
    uint48 pendingRevocationTime;
    bool adjustedForRevocation;
  }

  /// @notice The UNI token contract address on mainnet
  function UNI() external view returns (IUNI);

  /// @notice Total number of currently allocated shares
  /// @dev Always less than or equal to MAX_SHARES
  function totalShares() external view returns (uint16);

  /// @notice Access the Shares array by index
  /// @return Share unpacked: recipient, amount, revocationDelayDays, pendingRevocationTime,
  /// adjustedForRevocation
  function shares(uint256 index) external view returns (address, uint16, uint16, uint48, bool);

  /// @notice Executes the annual mint and distributes tokens proportionally to share holders
  /// @dev Can be called by anyone once per year. Mints based on allocated shares only, unallocated
  /// shares reduce inflation
  /// @dev The underlying UNI token contract reverts if called with > 2% of total supply
  //    or if < 365 days since the last
  function mint() external;

  /// @notice Grants shares of the UNI inflation to a recipient
  /// @dev Only callable by owner (UNI DAO). Reverts if total shares would exceed MAX_SHARES
  /// @param _recipient The address that will receive the minted UNI tokens
  /// @param _amount The number of shares to allocate (out of MAX_SHARES total)
  /// @param _revocationDelayDays The number of days notice required for a revocation of this share
  function grantShares(address _recipient, uint16 _amount, uint16 _revocationDelayDays) external;

  /// @notice Initiates the revocation process for a recipient's shares
  /// @dev Only callable by owner. Sets a timestamp after which revocation can be completed
  /// @param _index The index in the shares array of the allocation to revoke
  function initiateRevokeShares(uint256 _index) external;

  /// @notice Completes or updates share revocation based on timing relative to next mint
  /// @dev Can be called by anyone to update a share based on its pending revocation timing:
  ///   - If revocation completes before next mint: share is entirely removed
  ///   - If revocation extends into next mint period: share amount is reduced proportionally
  ///     to time remaining until revocation (e.g., 90 days into 365-day period = ~25% of shares)
  ///   - revokeShares must be called to update amounts for pending revocation
  /// @param _index The index in the shares array of the allocation to revoke or update
  function revokeShares(uint256 _index) external;

  /// @notice Transfers the UNI minter role to a new address
  /// @dev Only callable by owner. This is a critical operation that permanently transfers
  ///      the ability to mint UNI tokens to the new address. Once transferred, this contract
  ///      will no longer be able to mint UNI tokens unless the role is transferred back.
  /// @param _minter The address of the new minter contract or EOA
  function setMinter(address _minter) external;
}
