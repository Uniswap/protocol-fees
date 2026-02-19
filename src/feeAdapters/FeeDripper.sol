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
  // token jar address to receive the dripped fees
  address public immutable TOKEN_JAR;
  // the window of blocks over which the fees are released
  uint16 public releaseWindow = 1000;
  // mapping of currency to drip
  mapping(Currency => Drip) public drips;

  struct Drip {
    uint160 perBlockRate;
    uint48 endReleaseBlock;
    uint48 latestReleaseBlock;
  }

  constructor(address _tokenJar, address _owner) Owned(_owner) {
    if (_tokenJar == address(0)) revert InvalidTokenJar();
    TOKEN_JAR = _tokenJar;
  }

  /// @inheritdoc IFeeDripper
  function drip(Currency currency) external {
    // Copy the drip state to memory
    Drip memory dripState = drips[currency];

    (uint256 remainingBalance, uint256 releasedAmount, uint16 _releaseWindow) =
      _releasePreparation(currency, dripState);

    // We only check remainingBalance against type(uint160).max (not divided by releaseWindow)
    // because releaseWindow could be set to 1 by the owner at any time
    if (remainingBalance > type(uint160).max) {
      revert DripAmountTooLarge(remainingBalance / _releaseWindow, type(uint160).max);
    }

    // Update the drip state - reset the release window
    dripState.latestReleaseBlock = uint48(block.number);
    uint160 perBlockRate = uint160(remainingBalance / _releaseWindow);
    dripState.perBlockRate = perBlockRate;
    uint48 fullyReleasedBlock = uint48(block.number + _releaseWindow);
    dripState.endReleaseBlock = fullyReleasedBlock;
    drips[currency] = dripState;

    // Release the tokens to the token jar
    _releaseTokens(currency, releasedAmount);

    emit DripStarted(Currency.unwrap(currency), fullyReleasedBlock, perBlockRate);
  }

  /// @inheritdoc IFeeDripper
  function release(Currency currency) external {
    // Copy the drip state to memory
    Drip memory dripState = drips[currency];

    (, uint256 releasedAmount,) = _releasePreparation(currency, dripState);

    // Update the drip state - only the latest release block is updated to avoid
    // resetting the release window.
    dripState.latestReleaseBlock = uint48(Math.min(block.number, dripState.endReleaseBlock));
    drips[currency] = dripState;

    // Release the tokens to the token jar
    _releaseTokens(currency, releasedAmount);
  }

  /// @inheritdoc IFeeDripper
  function setReleaseWindow(uint16 _releaseWindow) external onlyOwner {
    if (_releaseWindow == 0) revert InvalidReleaseWindow();
    releaseWindow = _releaseWindow;
    emit ReleaseWindowSet(_releaseWindow);
  }

  receive() external payable {}

  function _releaseTokens(Currency currency, uint256 releasedAmount) internal {
    // Transfer released tokens to the token jar
    if (releasedAmount > 0) {
      currency.transfer(TOKEN_JAR, releasedAmount);
      emit Released(Currency.unwrap(currency), releasedAmount);
    }
  }

  function _releasePreparation(Currency currency, Drip memory dripState)
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

    // Calculate the remaining balance ahead of the release
    remainingBalance = currency.balanceOfSelf() - releasedAmount;

    // Cache the release window to avoid multiple storage reads within this call
    _releaseWindow = releaseWindow;

    // If the remaining balance is less than the release window, immediately release the remaining
    // balance to skip dust accumulation
    if (remainingBalance < _releaseWindow) {
      releasedAmount += remainingBalance;
      remainingBalance = 0;
    }

    return (remainingBalance, releasedAmount, _releaseWindow);
  }
}
