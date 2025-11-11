// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Owned} from "solmate/src/auth/Owned.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {IUNIVesting} from "./interfaces/IUNIVesting.sol";

/// @title UNIVesting
/// @notice A vesting contract that releases UNI tokens quarterly to a designated recipient
/// @dev The contract starts vesting on January 1, 2026 and allows withdrawals every quarter
/// (approximately 90 days) The owner must approve the contract to transfer UNI tokens on their
/// behalf
contract UNIVesting is Owned, IUNIVesting {
  using SafeTransferLib for ERC20;

  /// @inheritdoc IUNIVesting
  uint256 public constant START_TIME = 1_767_225_600;

  /// @inheritdoc IUNIVesting
  uint256 public immutable QUARTERLY_SECONDS = 7_776_000;

  /// @inheritdoc IUNIVesting
  ERC20 public immutable UNI;

  /// @inheritdoc IUNIVesting
  uint256 public QUARTERLY_VESTING_AMOUNT = 5_000_000e18;

  /// @inheritdoc IUNIVesting
  address public recipient;

  /// @inheritdoc IUNIVesting
  uint256 public lastQuarterlyTimestamp;

  /// @notice Restricts function access to either the contract owner or the recipient
  /// @dev Reverts with NotAuthorized if caller is neither owner nor recipient
  modifier onlyOwnerOrRecipient() {
    require(msg.sender == recipient || msg.sender == owner, NotAuthorized());
    _;
  }

  /// @notice Ensures that at least one quarter has passed since the last withdrawal
  /// @dev Reverts with OnlyQuarterly if called before the next quarterly period
  modifier onlyQuarterly() {
    require(block.timestamp >= lastQuarterlyTimestamp + QUARTERLY_SECONDS, OnlyQuarterly());
    _;
  }

  /// @notice Constructs a new UNIVesting contract
  /// @param _uni The address of the UNI token contract
  /// @param _recipient The address that will receive vested UNI tokens
  /// @dev Sets the caller as the owner and initializes lastQuarterlyTimestamp to START_TIME
  constructor(address _uni, address _recipient) Owned(msg.sender) {
    UNI = ERC20(_uni);
    recipient = _recipient;
    // checkpoint the quarterly timestamp to the start time
    lastQuarterlyTimestamp = START_TIME;
  }

  /// @inheritdoc IUNIVesting
  function updateVestingAmount(uint256 amount) public onlyOwner {
    require(quarters() == 0, CannotUpdateAmount());
    if (amount != QUARTERLY_VESTING_AMOUNT) {
      QUARTERLY_VESTING_AMOUNT = amount;
      emit VestingAmountUpdated(amount);
    }
  }

  /// @inheritdoc IUNIVesting
  function updateRecipient(address _recipient) public onlyOwnerOrRecipient {
    recipient = _recipient;
    emit RecipientUpdated(recipient);
  }

  /// @inheritdoc IUNIVesting
  function withdraw() public onlyQuarterly {
    uint256 numQuarters = quarters();
    uint256 totalAmount = numQuarters * QUARTERLY_VESTING_AMOUNT;
    /// Note that this timestamp might be in the past, but it should never be more than a quarter
    /// behind. This allows us to always collect exactly at the start of a quarter.
    lastQuarterlyTimestamp = lastQuarterlyTimestamp + numQuarters * QUARTERLY_SECONDS;
    UNI.safeTransferFrom(owner, recipient, totalAmount);
  }

  /// @inheritdoc IUNIVesting
  function quarters() public view returns (uint256) {
    return (block.timestamp - lastQuarterlyTimestamp) / QUARTERLY_SECONDS;
  }
}
