// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Owned} from "solmate/src/auth/Owned.sol";
import {IUNI} from "./interfaces/IUNI.sol";
import {IUNIMinter} from "./interfaces/IUNIMinter.sol";

/// @title UNIMinter
/// @notice A smart contract that manages the minting rights for UNI token, enabling proportional
/// distribution to multiple recipients
/// @dev This contract holds the minter role and allows annual minting with configurable share
/// allocations
/// @author Uniswap
/// @custom:security-contact security@uniswap.org
contract UNIMinter is IUNIMinter, Owned {
  /// @notice The mint cap in percentage terms (2% annual inflation)
  uint16 private constant MINT_CAP_PERCENT = 2;

  /// @notice The time between mints
  uint48 private constant MINT_PERIOD = uint48(365 days);

  /// @notice The total number of shares representing 100% of mintable tokens
  /// @dev Unallocated shares result in reduced inflation
  uint16 private constant MAX_SHARES = 10_000;

  /// @inheritdoc IUNIMinter
  IUNI public constant UNI = IUNI(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);

  /// @inheritdoc IUNIMinter
  uint16 public totalShares;

  /// @inheritdoc IUNIMinter
  Share[] public shares;

  /// @notice Creates a new UNIMinter instance
  /// @param _owner The initial admin address (UNI DAO) that can manage share allocations
  constructor(address _owner) Owned(_owner) {}

  /// @inheritdoc IUNIMinter
  function mint() external {
    require(totalShares != 0, NoShares());
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

  /// @inheritdoc IUNIMinter
  function grantShares(address _recipient, uint16 _amount, uint16 _revocationDelayDays)
    external
    onlyOwner
  {
    require(totalShares + _amount <= MAX_SHARES, InsufficientShares());
    shares.push(
      Share({
        recipient: _recipient,
        amount: _amount,
        revocationDelayDays: _revocationDelayDays,
        pendingRevocationTime: 0,
        adjustedForRevocation: false
      })
    );
    totalShares += _amount;
  }

  /// @inheritdoc IUNIMinter
  function initiateRevokeShares(uint256 _index) external onlyOwner {
    Share storage share = shares[_index];
    require(share.adjustedForRevocation == false, InvalidRevocation());
    share.pendingRevocationTime =
      uint48(block.timestamp + uint256(share.revocationDelayDays) * 1 days);
  }

  /// @inheritdoc IUNIMinter
  function revokeShares(uint256 _index) external {
    Share storage share = shares[_index];
    uint256 mintingAllowedAfter = UNI.mintingAllowedAfter();
    uint48 pendingRevocationTime = share.pendingRevocationTime;
    require(pendingRevocationTime != 0, NotPendingRevocation());

    // Revocation is ready before the next mint
    // It is safe to just remove them now since they won't be around for the next mint anyways
    if (pendingRevocationTime < mintingAllowedAfter) {
      totalShares -= share.amount;

      // Remove the share by swapping with the last and popping
      shares[_index] = shares[shares.length - 1];
      shares.pop();
    } else if (
      !share.adjustedForRevocation && pendingRevocationTime - mintingAllowedAfter < MINT_PERIOD
    ) {
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
      share.adjustedForRevocation = true;
    } else {
      // Revocation is not ready yet
      revert InvalidRevocation();
    }
  }

  /// @inheritdoc IUNIMinter
  function setMinter(address _minter) external onlyOwner {
    UNI.setMinter(_minter);
  }
}
