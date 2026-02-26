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

  // masks for the perBlockRate, endReleaseBlock, and latestReleaseBlock
  uint256 constant UINT160_MASK = 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
  uint256 constant UINT48_MASK = 0xFFFFFFFFFFFF;
  uint256 constant UINT16_MASK = 0xFFFF;

  // token jar address to receive the dripped fees
  address public immutable TOKEN_JAR;
  // the window of blocks over which the fees are released
  ReleaseSettings public releaseSettings =
    ReleaseSettings({releaseWindow: 1000, windowResetBps: 50});
  // mapping of currency to drip
  mapping(Currency => Drip) public drips;

  struct ReleaseSettings {
    uint16 releaseWindow; // the window of blocks over which the fees are released
    uint16 windowResetBps; // min new-deposit-to-previous-balance ratio (in bps) to reset the window
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
    // Copy the drip state to stack
    (uint160 perBlockRate, uint48 endReleaseBlock, uint48 latestReleaseBlock) =
      _readDripState(currency);

    (uint256 postDripBalance, uint256 releasedAmount, uint16 _releaseWindow) =
      _prepareRelease(currency, perBlockRate, endReleaseBlock, latestReleaseBlock);

    // We only check postDripBalance against type(uint160).max (not divided by releaseWindow)
    // because releaseWindow could be set to 1 by the owner at any time
    if (postDripBalance > type(uint160).max) postDripBalance = type(uint160).max;

    // Set the drip state - reset the release window
    uint160 updatedPerBlockRate = uint160(postDripBalance / _releaseWindow);

    // branchless: fullyReleasedBlock is block.number for zero remaining balance, otherwise
    // block.number + _releaseWindow
    uint256 fullyReleasedBlock = block.number;
    assembly ("memory-safe") {
      fullyReleasedBlock := add(fullyReleasedBlock, mul(_releaseWindow, gt(postDripBalance, 0)))
    }

    // Update the state. Uint48 for fullyReleasedBlock is safe for reasonable protocol horizon
    // assumption.
    _writeDripState(currency, updatedPerBlockRate, uint48(fullyReleasedBlock), uint48(block.number));

    // Release the tokens to the token jar
    _releaseTokens(currency, releasedAmount);
    if (postDripBalance > 0) {
      emit DripStarted(Currency.unwrap(currency), fullyReleasedBlock, updatedPerBlockRate);
    }
  }

  /// @inheritdoc IFeeDripper
  function release(Currency currency) external {
    // Copy the drip state to stack
    (uint160 perBlockRate, uint48 endReleaseBlock, uint48 latestReleaseBlock) =
      _readDripState(currency);

    (uint256 postDripBalance, uint256 releasedAmount,) =
      _prepareRelease(currency, perBlockRate, endReleaseBlock, latestReleaseBlock);

    latestReleaseBlock = uint48(Math.min(block.number, endReleaseBlock));
    if (postDripBalance == 0) {
      perBlockRate = 0;
      endReleaseBlock = latestReleaseBlock;
    }

    // Update the drip state
    _writeDripState(currency, perBlockRate, endReleaseBlock, latestReleaseBlock);

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

  function _writeDripState(
    Currency currency,
    uint160 perBlockRate,
    uint48 endReleaseBlock,
    uint48 latestReleaseBlock
  ) internal {
    // Used assembly to pack and store values directly from stack and skip memory allocation.
    assembly ("memory-safe") {
      mstore(0x00, currency)
      mstore(0x20, drips.slot)
      let dripPacked :=
        or(
          shl(208, latestReleaseBlock), // latestReleaseBlock
          or(
            shl(160, endReleaseBlock), // endReleaseBlock
            perBlockRate // perBlockRate
          )
        )
      sstore(keccak256(0x00, 0x40), dripPacked)
    }
  }

  function _readDripState(Currency currency)
    internal
    view
    returns (uint160 perBlockRate, uint48 endReleaseBlock, uint48 latestReleaseBlock)
  {
    // Read the drip state from storage and unpack into stack variables
    assembly ("memory-safe") {
      mstore(0x00, currency)
      mstore(0x20, drips.slot)
      let dripPacked := sload(keccak256(0x00, 0x40))

      perBlockRate := and(dripPacked, UINT160_MASK)
      endReleaseBlock := and(shr(160, dripPacked), UINT48_MASK)
      latestReleaseBlock := shr(208, dripPacked)
    }
  }

  function _readReleaseSettings()
    internal
    view
    returns (uint16 releaseWindow, uint16 windowResetBps)
  {
    assembly ("memory-safe") {
      let releaseSettingsPacked := sload(releaseSettings.slot)
      releaseWindow := and(releaseSettingsPacked, UINT16_MASK)
      windowResetBps := and(shr(16, releaseSettingsPacked), UINT16_MASK)
    }
  }

  function _prepareRelease(
    Currency currency,
    uint160 perBlockRate,
    uint48 endReleaseBlock,
    uint48 latestReleaseBlock
  ) internal view returns (uint256 postDripBalance, uint256 releasedAmount, uint16 _releaseWindow) {
    // Calculate the previous balance of the currency at last call
    uint256 previousBalance = (endReleaseBlock - latestReleaseBlock) * perBlockRate;

    // Calculate the amount of blocks passed since the last call
    uint256 blocksPassed = block.number - latestReleaseBlock;
    // Calculate the amount of tokens released since the last call
    // limit to previous balance if block.number > endReleaseBlock
    releasedAmount = Math.min(blocksPassed * perBlockRate, previousBalance);

    uint256 currentBalance = currency.balanceOfSelf();

    // Calculate the remaining balance ahead of the release
    postDripBalance = currentBalance - releasedAmount;

    // Cache the release settings in stack to avoid multiple storage reads within this call
    (uint16 _originalReleaseWindow, uint16 _windowResetBps) = _readReleaseSettings();

    _releaseWindow = _originalReleaseWindow;
    uint256 newDeposit = currentBalance - previousBalance;

    if (previousBalance > 0 && block.number < endReleaseBlock) {
      uint256 minBalanceForReset = (previousBalance * _windowResetBps) / BPS;
      if (newDeposit < minBalanceForReset) {
        _releaseWindow = uint16(endReleaseBlock - block.number);
      }
    }

    // If the remaining balance is less than the release window, immediately release the remaining
    // balance to skip dust accumulation
    if (postDripBalance < _originalReleaseWindow) {
      releasedAmount += postDripBalance;
      postDripBalance = 0;
    }

    return (postDripBalance, releasedAmount, _releaseWindow);
  }
}
