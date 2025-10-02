// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Owned} from "solmate/src/auth/Owned.sol";
import {IUNI} from "./interfaces/IUNI.sol";

/// @title UNIMinter
/// @notice A smart contract that manages the minting rights for UNI token, enabling proportional
/// distribution to multiple recipients
/// @dev This contract holds the minter role and allows annual minting with configurable share
/// allocations
/// @author Uniswap
contract UNIMinter is Owned {
  /// @notice Thrown when attempting to complete revocation before the delay period has elapsed
  error RevocationNotReady();
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
  struct Share {
    address recipient;
    uint16 amount;
    uint16 revocationDelayDays;
    uint48 pendingRevocationTime;
  }

  /// @notice The mint cap in percentage terms (2% annual inflation)
  uint16 private constant MINT_CAP_PERCENT = 2;

  /// @notice The time between mints
  uint48 private constant MINT_PERIOD = uint48(365 days);

  /// @notice The total number of shares representing 100% of mintable tokens
  /// @dev Unallocated shares result in reduced inflation
  uint16 private constant MAX_SHARES = 10_000;

  /// @notice The UNI token contract address on mainnet
  IUNI public constant UNI = IUNI(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);

  /// @notice Total number of currently allocated shares
  /// @dev Always less than or equal to MAX_SHARES
  uint16 public totalShares;

  /// @notice Array containing all active share allocations
  /// @dev Iterate through this array to distribute minted tokens
  Share[] public shares;

  /// @notice Creates a new UNIMinter instance
  /// @param _owner The initial admin address (UNI DAO) that can manage share allocations
  constructor(address _owner) Owned(_owner) {}

  /// @notice Executes the annual mint and distributes tokens proportionally to share holders
  /// @dev Can be called by anyone once per year. Mints based on allocated shares only, unallocated
  /// shares reduce inflation
  /// @dev The underlying UNI token contract reverts if called with > 2% of total supply
  //    or if < 365 days since the last
  function mint() external {
    if (totalShares == 0) revert NoShares();
    uint256 mintCap = UNI.totalSupply() * MINT_CAP_PERCENT / 100;
    uint256 mintAmount = mintCap * totalShares / MAX_SHARES;
    UNI.mint(address(this), mintAmount);

    // Distribute to recipients based on their shares
    Share memory share;
    uint256 recipientAmount;
    for (uint256 i; i < shares.length; i++) {
      share = shares[i];
      recipientAmount = mintAmount * share.amount / totalShares;
      if (recipientAmount > 0) UNI.transfer(share.recipient, recipientAmount);
    }
  }

  /// @notice Grants shares of the UNI inflation to a recipient
  /// @dev Only callable by owner (UNI DAO). Reverts if total shares would exceed MAX_SHARES
  /// @param _recipient The address that will receive the minted UNI tokens
  /// @param _amount The number of shares to allocate (out of MAX_SHARES total)
  /// @param _revocationDelayDays The number of days notice required for a revocation of this share
  function grantShares(address _recipient, uint16 _amount, uint16 _revocationDelayDays)
    external
    onlyOwner
  {
    if (totalShares + _amount > MAX_SHARES) revert InsufficientShares();
    shares.push(
      Share({
        recipient: _recipient,
        amount: _amount,
        revocationDelayDays: _revocationDelayDays,
        pendingRevocationTime: 0
      })
    );
    totalShares += _amount;
  }

  /// @notice Initiates the revocation process for a recipient's shares
  /// @dev Only callable by owner. Sets a timestamp after which revocation can be completed
  /// @param _index The index in the shares array of the allocation to revoke
  function initiateRevokeShares(uint256 _index) external onlyOwner {
    Share storage share = shares[_index];
    share.pendingRevocationTime =
      uint48(block.timestamp + uint256(share.revocationDelayDays) * 1 days);
  }

  /// @notice Completes or updates share revocation based on timing relative to next mint
  /// @dev Can be called by anyone to update a share based on its pending revocation timing:
  ///   - If revocation completes before next mint: share is entirely removed
  ///   - If revocation extends into next mint period: share amount is reduced proportionally
  ///     to time remaining until revocation (e.g., 90 days into 365-day period = ~25% of shares)
  ///   - revokeShares must be called to update amounts for pending revocation
  /// @param _index The index in the shares array of the allocation to revoke or update
  function revokeShares(uint256 _index) external {
    Share storage share = shares[_index];
    uint256 mintingAllowedAfter = UNI.mintingAllowedAfter();
    uint48 pendingRevocationTime = share.pendingRevocationTime;
    if (pendingRevocationTime == 0) revert NotPendingRevocation();

    // Revocation is ready before the next mint
    // It is safe to just remove them now since they won't be around for the next mint anyways
    if (pendingRevocationTime < mintingAllowedAfter) {
      totalShares -= share.amount;

      // Remove the share by swapping with the last and popping
      shares[_index] = shares[shares.length - 1];
      shares.pop();
    } else if (pendingRevocationTime - mintingAllowedAfter < MINT_PERIOD) {
      // Revocation is ready after the next mint but before the one after that
      // Update their shares such that they receive a partial mint proportional to the remaining
      // time until revocation after the mint
      // e.g. if the share expires halfway through the next mint period, they get half their share
      // and subsequently can be fully revoked after the next mint
      uint16 originalShareAmount = share.amount;
      share.amount =
        uint16((pendingRevocationTime - mintingAllowedAfter) * share.amount / MINT_PERIOD);
      // subtract the newly removed shares
      totalShares -= (originalShareAmount - share.amount);
    } else {
      // Revocation is not ready yet
      revert RevocationNotReady();
    }
  }

  /// @notice Transfers the UNI minter role to a new address
  /// @dev Only callable by owner. This is a critical operation that permanently transfers
  ///      the ability to mint UNI tokens to the new address. Once transferred, this contract
  ///      will no longer be able to mint UNI tokens unless the role is transferred back.
  /// @param _minter The address of the new minter contract or EOA
  function setMinter(address _minter) external onlyOwner {
    UNI.setMinter(_minter);
  }
}
