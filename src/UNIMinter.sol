// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Owned} from "solmate/src/auth/Owned.sol";
import {IUNI} from "./interfaces/IUNI.sol";
import {IUNIMinter} from "./interfaces/IUNIMinter.sol";

/// @title UNIMinter
/// @notice A smart contract that manages the minting rights for UNI token, enabling proportional
/// distribution to multiple recipients
/// @dev This contract holds the minter role and allows annual minting with configurable allocations
/// @author Uniswap
/// @custom:security-contact security@uniswap.org
contract UNIMinter is IUNIMinter, Owned {
  /// @notice The mint cap in percentage terms (2% annual inflation)
  uint16 private constant MINT_CAP_PERCENT = 2;

  /// @notice The time between mints
  uint48 private constant MINT_PERIOD = uint48(365 days);

  /// @notice The total number of units representing 100% of mintable tokens
  /// @dev Unallocated units result in reduced inflation
  uint16 private constant MAX_UNITS = 10_000;

  /// @notice The start time for minting
  /// @dev equivalent to January 1, 2026 00:00:00 UTC
  uint256 public constant START_TIME = 1_767_225_600;

  /// @inheritdoc IUNIMinter
  IUNI public constant UNI = IUNI(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);

  /// @inheritdoc IUNIMinter
  uint16 public totalUnits;

  /// @inheritdoc IUNIMinter
  Split[] public splits;

  /// @notice Creates a new UNIMinter instance
  /// @param _owner The initial admin address (UNI DAO) that can manage split allocations
  constructor(address _owner) Owned(_owner) {}

  /// @inheritdoc IUNIMinter
  function mint() external {
    require(block.timestamp >= START_TIME, MintingNotStarted());
    require(totalUnits != 0, NoUnits());
    uint256 mintCap = UNI.totalSupply() * MINT_CAP_PERCENT / 100;
    uint256 mintAmount = mintCap * totalUnits / MAX_UNITS;
    UNI.mint(address(this), mintAmount);

    // Distribute to recipients based on their splits
    Split memory split;
    uint256 recipientAmount;
    for (uint256 i; i < splits.length; i++) {
      split = splits[i];
      recipientAmount = mintAmount * split.units / totalUnits;
      if (recipientAmount > 0) UNI.transfer(split.recipient, recipientAmount);
    }
  }

  /// @inheritdoc IUNIMinter
  function grantSplit(address _recipient, uint16 _units, uint16 _revocationDelayDays)
    external
    onlyOwner
  {
    require(totalUnits + _units <= MAX_UNITS, InsufficientUnits());
    splits.push(
      Split({
        recipient: _recipient,
        units: _units,
        revocationDelayDays: _revocationDelayDays,
        pendingRevocationTime: 0,
        adjustedForRevocation: false
      })
    );
    totalUnits += _units;
  }

  /// @inheritdoc IUNIMinter
  function initiateRevokeSplit(uint256 _index) external onlyOwner {
    Split storage split = splits[_index];
    require(split.adjustedForRevocation == false, InvalidRevocation());
    split.pendingRevocationTime =
      uint48(block.timestamp + uint256(split.revocationDelayDays) * 1 days);
  }

  /// @inheritdoc IUNIMinter
  function revokeSplit(uint256 _index) external {
    Split storage split = splits[_index];
    uint256 mintingAllowedAfter = UNI.mintingAllowedAfter();
    uint48 pendingRevocationTime = split.pendingRevocationTime;
    require(pendingRevocationTime != 0, NotPendingRevocation());

    // Revocation is ready before the next mint
    // It is safe to just remove them now since they won't be around for the next mint anyways
    if (pendingRevocationTime < mintingAllowedAfter) {
      totalUnits -= split.units;

      // Remove the split by swapping with the last and popping
      splits[_index] = splits[splits.length - 1];
      splits.pop();
    } else if (
      !split.adjustedForRevocation && pendingRevocationTime - mintingAllowedAfter < MINT_PERIOD
    ) {
      // Revocation is ready after the next mint but before the one after that
      // Update their splits such that they receive a partial mint proportional to the remaining
      // time until revocation after the mint
      // e.g. if the split expires halfway through the next mint period, they get half their split
      // and subsequently can be fully revoked after the next mint
      uint16 originalSplitUnits = split.units;
      split.units =
        uint16((pendingRevocationTime - mintingAllowedAfter) * originalSplitUnits / MINT_PERIOD);
      // subtract the newly removed splits
      totalUnits -= (originalSplitUnits - split.units);
      split.adjustedForRevocation = true;
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
