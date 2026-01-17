// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

/// @notice Struct representing an active tap for a given currency
struct Tap {
  uint192 balance; /// @notice The last synced balance of the tap
  uint32 head; /// @notice The head of the linked list of kegs
  uint32 tail; /// @notice The tail of the linked list of kegs
}

/// @notice Struct representing a unique currency deposit
struct Keg {
  Currency currency; /// @notice The currency associated with the keg
  uint48 endBlock; /// @notice The block at which the deposit will be fully released
  uint48 lastReleaseBlock; /// @notice The block at which the last release was made
  uint192 perBlockReleaseAmount; /// @notice The absolute amount of the currency released per block
  uint32 next; /// @notice The next keg in the linked list
}

/// @title IFeeTapper
interface IFeeTapper {
  /// @notice Error thrown when the balance is too large
  error AmountTooLarge();

  /// @notice Error thrown when the release rate is zero or larger than BPS
  error ReleaseRateOutOfBounds();

  /// @notice Error thrown when the rate does not evenly divide BPS
  error InvalidReleaseRate();

  /// @notice Emitted when a new deposit is synced
  /// @param id The unique id of the deposit
  /// @param currency The currency being deposited
  /// @param amount The amount of protocol fees deposited
  /// @param endBlock The block at which the deposit will be fully released
  event Deposited(uint64 indexed id, address indexed currency, uint192 amount, uint64 endBlock);

  /// @notice Emitted when a Tap is synced
  /// @param currency The currency being synced
  /// @param balance The new balance of the tap
  event Synced(address indexed currency, uint192 balance);

  /// @notice Emitted when protocol fees are released
  /// @param currency The currency being released
  /// @param amount The amount of protocol fees released
  event Released(address indexed currency, uint192 amount);

  /// @notice Emitted when the release rate is set
  /// @param rate The new release rate
  event ReleaseRateSet(uint24 rate);

  /// @notice Sets the release rate for accrued protocol fees in basis points per block. Only
  /// callable by the owner. @dev Rate must be non zero and <= BPS and evenly divisible by BPS.
  /// @param _perBlockReleaseRate The new release rate in basis points per block
  function setReleaseRate(uint24 _perBlockReleaseRate) external;

  /// @notice Syncs the fee tapper with received protocol fees. Callable by anyone
  /// @dev Creates a new Tap for the currency if it does not exist already
  /// @param currency The currency to sync
  function sync(Currency currency) external;

  /// @notice Releases a single keg. Each keg is a unique deposit of fees
  /// @dev Unlike releaseAll this function does not remove empty kegs from the list
  /// @param id The id of the keg to release
  function release(uint32 id) external returns (uint192);

  /// @notice Releases all accumulated protocol fees for a given currency to the token jar
  /// @dev This function will loop through all active kegs for the given currency
  /// @param currency The currency to release
  function releaseAll(Currency currency) external returns (uint192);

  /// Getters

  /// @notice Gets the tap for the given currency
  /// @param currency The currency to get the tap for
  function taps(Currency currency) external view returns (Tap memory);

  /// @notice Gets the keg for the given id
  /// @dev You MUST find the corresponding tap holding the keg before using the returned values
  /// @param id The id of the keg to get
  function kegs(uint32 id) external view returns (Keg memory);
}
