// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IFeeDripper} from "../interfaces/IFeeDripper.sol";

/// @title FeeDripper
/// @notice A contract that smoothes the flow of fees into TokenJar over a configurable block window
/// @dev Fee-on-transfer and rebasing tokens are not supported. This is consistent with Uniswap v4
///      PoolManager and CCA auctions, which also assume exact-amount transfers.
/// @custom:security-contact security@uniswap.org
contract FeeDripper is Owned, IFeeDripper {
  /// @notice Basis points denominator
  uint24 public constant BPS = 10_000;
  // token jar address to receive the dripped fees
  address public immutable TOKEN_JAR;
  // the window of blocks over which the fees are released
  ReleaseSettings public releaseSettings =
    ReleaseSettings({releaseWindow: 1000, windowResetBps: 50});
  // mapping of currency to drip
  mapping(Currency => Drip) public drips;

  struct ReleaseSettings {
    uint16 releaseWindow;
    uint16 windowResetBps;
  }

  struct Drip {
    uint160 perBlockRate;
    uint48 endReleaseBlock;
    uint48 latestReleaseBlock;
  }

  constructor(address _tokenJar, address _owner) Owned(_owner) {
    if (_owner == address(0)) revert InvalidOwner();
    if (_tokenJar == address(0)) revert InvalidTokenJar();
    TOKEN_JAR = _tokenJar;
  }

  /// @inheritdoc IFeeDripper
  function drip(Currency currency) external {
    // Copy the drip state to memory
    Drip memory dripState = drips[currency];

    (uint256 remainingBalance, uint256 releasedAmount, uint16 _releaseWindow) =
      _prepareRelease(currency, dripState);

    // We only check remainingBalance against type(uint160).max (not divided by releaseWindow)
    // because releaseWindow could be set to 1 by the owner at any time
    if (remainingBalance > type(uint160).max) {
      revert DripAmountTooLarge(remainingBalance, type(uint160).max);
    }

    // Set the drip state - reset the release window
    uint160 perBlockRate = uint160(remainingBalance / _releaseWindow);
    uint256 fullyReleasedBlock = block.number;
    // branchless: fullyReleasedBlock is block.number for zero remaining balance, otherwise
    // block.number + _releaseWindow
    assembly ("memory-safe") {
      fullyReleasedBlock := add(fullyReleasedBlock, mul(_releaseWindow, gt(remainingBalance, 0)))
    }
    // Convert to uint48 (safe for reasonable protocol horizon assumption)
    uint48 fullyReleasedBlock48 = uint48(fullyReleasedBlock);

    // Update the state. Even for zero remaining balance, we update instead of deleting to avoid
    // re-initializing the drip state. Used assembly to pack and store values directly from stack.
    assembly ("memory-safe") {
      mstore(0x00, currency)
      mstore(0x20, drips.slot)
      let dripPacked :=
        or( /* latestReleaseBlock */
          shl(208, number()),
          or( /* endReleaseBlock */ shl(160, fullyReleasedBlock48), /* perBlockRate */ perBlockRate)
        )
      sstore(keccak256(0x00, 0x40), dripPacked)
    }

    // Release the tokens to the token jar
    _releaseTokens(currency, releasedAmount);
    if (remainingBalance > 0) {
      emit DripStarted(Currency.unwrap(currency), fullyReleasedBlock48, perBlockRate);
    }
  }

  /// @inheritdoc IFeeDripper
  function release(Currency currency) external {
    // Copy the drip state to memory
    Drip memory dripState = drips[currency];

    (, uint256 releasedAmount,) = _prepareRelease(currency, dripState);

    // Update the drip state - only the latest release block is updated to avoid
    // resetting the release window.
    dripState.latestReleaseBlock = uint48(Math.min(block.number, dripState.endReleaseBlock));
    drips[currency] = dripState;

    // Release the tokens to the token jar
    _releaseTokens(currency, releasedAmount);
  }

  /// @inheritdoc IFeeDripper
  function setReleaseSettings(uint16 _releaseWindow, uint16 _windowResetBps) external onlyOwner {
    if (_releaseWindow == 0) revert InvalidReleaseWindow();
    if (_windowResetBps > BPS) revert InvalidWindowResetBps();
    releaseSettings =
      ReleaseSettings({releaseWindow: _releaseWindow, windowResetBps: _windowResetBps});
    emit ReleaseSettingsSet(_releaseWindow, _windowResetBps);
  }

  receive() external payable {}

  function _releaseTokens(Currency currency, uint256 releasedAmount) internal {
    // Transfer released tokens to the token jar
    if (releasedAmount > 0) {
      currency.transfer(TOKEN_JAR, releasedAmount);
      emit Released(Currency.unwrap(currency), releasedAmount);
    }
  }

  function _prepareRelease(Currency currency, Drip memory dripState)
    internal
    view
    returns (uint256 remainingBalance, uint256 releasedAmount, uint16 _releaseWindow)
  {
    // Calculate the previous balance of the currency at last call
    uint256 previousBalance =
      (dripState.endReleaseBlock - dripState.latestReleaseBlock) * dripState.perBlockRate;

    // Calculate the amount of blocks passed since the last call
    uint256 blocksPassed = block.number - dripState.latestReleaseBlock;
    // Calculate the amount of tokens released since the last call
    releasedAmount = Math.min(blocksPassed * dripState.perBlockRate, previousBalance);

    uint256 currentBalance = currency.balanceOfSelf();

    // Calculate the remaining balance ahead of the release
    remainingBalance = currentBalance - releasedAmount;

    // Cache the release settings to avoid multiple storage reads within this call
    ReleaseSettings memory _releaseSettings = releaseSettings;

    _releaseWindow = _releaseSettings.releaseWindow;
    uint256 newDeposit = currentBalance - previousBalance;

    if (previousBalance > 0 && block.number < dripState.endReleaseBlock) {
      uint256 minBalanceForReset = (previousBalance * _releaseSettings.windowResetBps) / BPS;
      if (newDeposit < minBalanceForReset) {
        _releaseWindow = uint16(dripState.endReleaseBlock - block.number);
      }
    }

    // If the remaining balance is less than the release window, immediately release the remaining
    // balance to skip dust accumulation
    if (remainingBalance < _releaseSettings.releaseWindow) {
      releasedAmount += remainingBalance;
      remainingBalance = 0;
    }

    return (remainingBalance, releasedAmount, _releaseWindow);
  }
}
