// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {
  BokkyPooBahsDateTimeLibrary as DateTime
} from "BokkyPooBahsDateTimeLibrary/contracts/BokkyPooBahsDateTimeLibrary.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {IUNIVesting} from "./interfaces/IUNIVesting.sol";

/// @title UNIVesting
/// @notice A vesting contract that releases UNI tokens quarterly to a designated recipient
/// @dev The contract unlocks its first tranche on Jan 1, 2026 and allows withdrawals every calendar
/// quarter thereafter. The owner must maintain an ERC20 allowance for the contract to transfer UNI
/// tokens. Supports partial withdrawals when allowance is less than vested amount.
contract UNIVesting is Owned, IUNIVesting {
  using SafeTransferLib for ERC20;

  /// @notice Number of months in a quarter
  uint256 private constant MONTHS_PER_QUARTER = 3;

  /// @dev equivalent to January 1, 2026 00:00:00 UTC
  uint256 private constant FIRST_UNLOCK_TIMESTAMP = 1_767_225_600;

  /// @inheritdoc IUNIVesting
  ERC20 public immutable UNI;

  /// @inheritdoc IUNIVesting
  uint256 public quarterlyVestingAmount = 5_000_000 ether;

  /// @inheritdoc IUNIVesting
  address public recipient;

  /// @inheritdoc IUNIVesting
  uint48 public lastUnlockTimestamp;

  /// @notice Restricts function access to either the contract owner or the recipient
  /// @dev Reverts with NotAuthorized if caller is neither owner nor recipient
  modifier onlyOwnerOrRecipient() {
    require(msg.sender == recipient || msg.sender == owner, NotAuthorized());
    _;
  }

  /// @notice Constructs a new UNIVesting contract
  /// @param _uni The address of the UNI token contract
  /// @param _recipient The address that will receive vested UNI tokens
  /// @dev The deployer becomes the owner. The owner must approve this contract
  /// to spend their UNI tokens for vesting to work properly.
  constructor(address _uni, address _recipient) Owned(msg.sender) {
    UNI = ERC20(_uni);
    updateRecipient(_recipient);
    // set the quarterly timestamp such that the first unlock occurs on FIRST_UNLOCK_TIMESTAMP
    lastUnlockTimestamp = uint48(DateTime.subMonths(FIRST_UNLOCK_TIMESTAMP, MONTHS_PER_QUARTER));
  }

  /// @inheritdoc IUNIVesting
  /// @dev Can only be called by the owner and only when no active quarters are available to
  /// withdraw (i.e., quartersPassed() == 0). This prevents changing the amount when tokens have
  /// already
  /// vested and are waiting to be claimed
  function updateVestingAmount(uint256 amount) external onlyOwner {
    require(amount != quarterlyVestingAmount, NoChangeUpdate());
    require(quartersPassed() == 0, CannotUpdateAmount());
    quarterlyVestingAmount = amount;
    emit VestingAmountUpdated(amount);
  }

  /// @inheritdoc IUNIVesting
  /// @dev Both the owner and current recipient can update the recipient address.
  /// This allows the recipient to transfer their vesting rights to another address.
  function updateRecipient(address _recipient) public onlyOwnerOrRecipient {
    require(_recipient != recipient, NoChangeUpdate());
    recipient = _recipient;
    emit RecipientUpdated(recipient);
  }

  /// @inheritdoc IUNIVesting
  /// @dev This function can be called by anyone (not just the recipient).
  /// Handles both full and partial withdrawals based on the owner's allowance.
  /// If allowance < vested amount, only withdraws what's allowed and updates
  /// the timestamp accordingly. The remaining quarters can be withdrawn later.
  /// Relies on owner maintaining sufficient ERC20 allowance.
  /// If owner revokes allowance, withdrawals will fail with InsufficientAllowance.
  function withdraw() external {
    uint48 numQuarters = quartersPassed();
    require(numQuarters > 0, OnlyQuarterly());

    uint256 _quarterlyVestingAmount = quarterlyVestingAmount;
    uint256 vestedAmount = _quarterlyVestingAmount * uint256(numQuarters);
    uint256 currentAllowance = UNI.allowance(owner, address(this));

    uint48 quartersPaid;

    if (currentAllowance < vestedAmount) {
      // Partial withdrawal path: owner's allowance is less than vested amount
      // Calculate how many complete quarters we can withdraw with current allowance
      uint48 withdrawableQuarters = uint48(currentAllowance / _quarterlyVestingAmount);

      require(withdrawableQuarters > 0, InsufficientAllowance());

      // Only advance timestamp by the quarters we're actually paying out
      // This ensures remaining quarters can be withdrawn later when allowance increases
      lastUnlockTimestamp =
        uint48(DateTime.addMonths(lastUnlockTimestamp, withdrawableQuarters * MONTHS_PER_QUARTER));

      vestedAmount = _quarterlyVestingAmount * uint256(withdrawableQuarters);
      quartersPaid = withdrawableQuarters;
    } else {
      // Full withdrawal path: sufficient allowance for all vested quarters
      // Advance timestamp by all quarters that have vested
      lastUnlockTimestamp =
        uint48(DateTime.addMonths(lastUnlockTimestamp, numQuarters * MONTHS_PER_QUARTER));

      quartersPaid = numQuarters;
    }

    UNI.safeTransferFrom(owner, recipient, vestedAmount);
    emit Withdrawn(recipient, vestedAmount, quartersPaid);
  }

  /// @inheritdoc IUNIVesting
  /// @dev Uses calendar-based quarters (3 months each)
  /// Returns 0 if no quarters have passed since last withdrawal.
  function quartersPassed() public view returns (uint48) {
    uint48 _lastUnlockTimestamp = lastUnlockTimestamp;
    if (block.timestamp < _lastUnlockTimestamp) return 0;
    return uint48(DateTime.diffMonths(_lastUnlockTimestamp, block.timestamp) / MONTHS_PER_QUARTER);
  }
}
