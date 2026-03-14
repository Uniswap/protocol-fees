// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Tap, Keg, IFeeTapper} from "../interfaces/IFeeTapper.sol";

/// @title FeeTapper
/// @notice Singleton contract which handles the streaming of incoming protocol fees to TokenJar
contract FeeTapper is IFeeTapper, Ownable {
  using CurrencyLibrary for Currency;

  address public immutable tokenJar;

  /// @notice Mapping of currencies to Taps
  mapping(Currency => Tap) private $_taps;
  /// @notice Linked list of kegs. Taps manage the head and tail of their respective kegs.
  mapping(uint32 => Keg) private $_kegs;
  /// @notice The id of the next keg to be created
  uint32 public nextId;

  /// @notice Basis points denominator
  uint24 public constant BPS = 10_000;
  /// @notice The release rate for accrued protocol fees in basis points per block.
  ///         For example, at 10 basis points the full amount is released over 1_000 blocks.
  /// @dev    This helps smooth out the release of fees which is useful for integrating with
  /// TokenJar fee exchangers.
  uint24 public perBlockReleaseRate = 10;

  /// @notice The maximum supported balance to prevent overflowing a uint192
  uint192 public constant MAX_BALANCE = type(uint192).max / BPS;

  constructor(address _tokenJar, address _owner) Ownable(_owner) {
    tokenJar = _tokenJar;
  }

  /// @notice Gets the tap for the given currency, if active
  function taps(Currency currency) external view returns (Tap memory) {
    return $_taps[currency];
  }

  /// @notice Gets the keg for the given id
  function kegs(uint32 id) external view returns (Keg memory) {
    return $_kegs[id];
  }

  /// @inheritdoc IFeeTapper
  function setReleaseRate(uint24 _perBlockReleaseRate) external onlyOwner {
    if (_perBlockReleaseRate == 0 || _perBlockReleaseRate > BPS) revert ReleaseRateOutOfBounds();
    if (BPS % _perBlockReleaseRate != 0) revert InvalidReleaseRate();
    perBlockReleaseRate = _perBlockReleaseRate;
    emit ReleaseRateSet(_perBlockReleaseRate);
  }

  /// @inheritdoc IFeeTapper
  function sync(Currency currency) external {
    Tap storage $tap = $_taps[currency];
    // Silently truncates any received balances over uint192.max
    uint192 balance = uint192(currency.balanceOfSelf());
    // Revert if the amount added to the tap would eventually overflow a uint192
    if (balance > MAX_BALANCE) revert AmountTooLarge();
    uint192 oldBalance = $tap.balance;
    // noop if there hasn't been a change in balance
    if (balance == oldBalance) return;

    unchecked {
      nextId++;
    }
    uint32 next = nextId;

    uint48 endBlock = uint48(block.number + BPS / perBlockReleaseRate);
    uint192 amount = balance - oldBalance;

    $_kegs[next] = Keg({
      currency: currency,
      perBlockReleaseAmount: amount * perBlockReleaseRate,
      lastReleaseBlock: uint48(block.number),
      endBlock: endBlock,
      next: 0
    });
    if ($tap.head == 0) {
      $tap.head = next;
      $tap.tail = next;
    } else {
      $_kegs[$tap.tail].next = next;
      $tap.tail = next;
    }
    $tap.balance = balance;

    emit Deposited(next, Currency.unwrap(currency), amount, endBlock);
    emit Synced(Currency.unwrap(currency), balance);
  }

  /// @inheritdoc IFeeTapper
  function release(uint32 id) external returns (uint192) {
    Keg memory keg = $_kegs[id];
    return _process(keg.currency, _release(keg, id));
  }

  /// @inheritdoc IFeeTapper
  function releaseAll(Currency currency) external returns (uint192) {
    return _process(currency, _releaseAll(currency));
  }

  /// @notice Releases a single keg for a given currency
  /// @param id The id of the keg to release
  function _release(Keg memory keg, uint32 id) internal returns (uint192 releasedAmount) {
    uint48 minBlock = uint48(_min(block.number, keg.endBlock));
    releasedAmount = uint192(keg.perBlockReleaseAmount * (minBlock - keg.lastReleaseBlock));
    // Set the lastReleaseBlock such that after the endBlock, releasedAmount will be zero
    $_kegs[id].lastReleaseBlock = minBlock;
    return releasedAmount;
  }

  /// @notice Releases all kegs for a given currency
  function _releaseAll(Currency currency) internal returns (uint192 releasedAmount) {
    Tap storage $tap = $_taps[currency];
    if ($tap.balance == 0) return 0;

    uint32 prev = 0;
    uint32 curr = $tap.head;
    uint256 blockNumber = block.number;
    // Itereate through all kegs. This can be very costly if there are lot of kegs.
    while (curr != 0) {
      Keg memory keg = $_kegs[curr];
      uint32 next = keg.next;

      releasedAmount += _release(keg, curr);

      if (keg.endBlock <= blockNumber) {
        // unlink the current keg
        if (prev == 0) {
          // deleting head
          $tap.head = next;
        } else {
          $_kegs[prev].next = next;
        }
        // if we removed the tail (next == 0 after unlink), update tail
        if (next == 0) $tap.tail = prev;
        delete $_kegs[curr];
      } else {
        // only advance prev when the current keg remains linked
        prev = curr;
      }

      curr = next;
    }
    return releasedAmount;
  }

  /// @notice Transfers the released amount to the token jar
  function _process(Currency _currency, uint192 _releasedAmount) internal returns (uint192) {
    // Because we deferred dividing by BPS when storing the perBlockReleaseAmount, we need to divide
    // now
    uint192 toRelease = _releasedAmount / BPS;
    // Update the tap balance
    $_taps[_currency].balance -= toRelease;

    if (toRelease > 0) {
      _currency.transfer(tokenJar, toRelease);
      emit Released(Currency.unwrap(_currency), toRelease);
    }
    return toRelease;
  }

  function _min(uint256 a, uint256 b) internal pure returns (uint256) {
    return a < b ? a : b;
  }

  /// @notice Receives ETH
  receive() external payable {}
}
