// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

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
  uint16 public constant BPS = 10_000;

  // masks for the perBlockRate, endReleaseBlock, and latestReleaseBlock
  uint256 private constant UINT160_MASK = 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
  uint256 private constant UINT48_MASK = 0xFFFFFFFFFFFF;
  uint256 private constant UINT16_MASK = 0xFFFF;

  // token jar address to receive the dripped fees
  address public immutable TOKEN_JAR;
  // the window of blocks over which the fees are released
  ReleaseSettings public releaseSettings =
    ReleaseSettings({releaseWindow: 2000, windowResetBps: 50});
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

  constructor(address tokenJar, address owner) Owned(owner) {
    require(owner != address(0), InvalidOwner());
    require(tokenJar != address(0), InvalidTokenJar());
    TOKEN_JAR = tokenJar;
  }

  /// @inheritdoc IFeeDripper
  function drip(Currency currency) external {
    // Copy the drip state to stack
    (uint160 perBlockRate, uint48 endReleaseBlock, uint48 latestReleaseBlock) =
      _readDripState(currency);

    (uint256 postDripBalance, uint256 releasedAmount, uint16 releaseWindow) =
      _prepareRelease(currency, perBlockRate, endReleaseBlock, latestReleaseBlock);

    // We only check postDripBalance against type(uint160).max (not divided by releaseWindow)
    // because releaseWindow could be set to 1 by the owner at any time
    if (postDripBalance > type(uint160).max) postDripBalance = type(uint160).max;

    // Update the per block rate for the new drip timeframe
    uint160 updatedPerBlockRate = uint160(postDripBalance / releaseWindow);

    // branchless: fullyReleasedBlock is block.number for zero remaining balance, otherwise
    // block.number + releaseWindow
    uint256 fullyReleasedBlock = block.number;
    assembly ("memory-safe") {
      fullyReleasedBlock := add(fullyReleasedBlock, mul(releaseWindow, gt(postDripBalance, 0)))
    }

    // Update the state. Uint48 for fullyReleasedBlock is safe for reasonable
    // protocol horizon assumption.
    _writeDripState(currency, updatedPerBlockRate, uint48(fullyReleasedBlock), uint48(block.number));

    // Release the tokens to the token jar
    _releaseTokens(currency, releasedAmount);
    if (postDripBalance > 0) {
      emit DripUpdated(Currency.unwrap(currency), fullyReleasedBlock, updatedPerBlockRate);
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
  function setReleaseSettings(uint16 releaseWindow, uint16 windowResetBps) external onlyOwner {
    require(releaseWindow > 0, InvalidReleaseWindow());
    require(windowResetBps <= BPS, InvalidWindowResetBps());
    releaseSettings =
      ReleaseSettings({releaseWindow: releaseWindow, windowResetBps: windowResetBps});
    emit ReleaseSettingsSet(releaseWindow, windowResetBps);
  }

  receive() external payable {}

  /// @dev Transfers tokens to the token jar. Emits the Released event.
  function _releaseTokens(Currency currency, uint256 releasedAmount) private {
    // Transfer released tokens to the token jar
    if (releasedAmount > 0) {
      currency.transfer(TOKEN_JAR, releasedAmount);
      emit Released(Currency.unwrap(currency), releasedAmount);
    }
  }

  /// @dev Packs and writes the drip state to a single slot in storage.
  function _writeDripState(
    Currency currency,
    uint160 perBlockRate,
    uint48 endReleaseBlock,
    uint48 latestReleaseBlock
  ) private {
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

  /// @dev Reads the drip state from storage. Skips memory and reads directly to stack
  function _readDripState(Currency currency)
    private
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

  /// @dev Reads the release settings from storage. Skips memory and reads directly to stack
  function _readReleaseSettings()
    private
    view
    returns (uint16 releaseWindow, uint16 windowResetBps)
  {
    assembly ("memory-safe") {
      let releaseSettingsPacked := sload(releaseSettings.slot)
      releaseWindow := and(releaseSettingsPacked, UINT16_MASK)
      windowResetBps := and(shr(16, releaseSettingsPacked), UINT16_MASK)
    }
  }

  /// @dev Shared logic to calculate accrued amount and prepare the release of those tokens.
  function _prepareRelease(
    Currency currency,
    uint160 perBlockRate,
    uint48 endReleaseBlock,
    uint48 latestReleaseBlock
  ) private view returns (uint256 postDripBalance, uint256 releasedAmount, uint16 releaseWindow) {
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
    (uint16 originalReleaseWindow, uint16 windowResetBps) = _readReleaseSettings();

    // By default, extend the drip timeframe by the original release window.
    releaseWindow = originalReleaseWindow;
    uint256 newDeposit = currentBalance - previousBalance;

    // Threshold is based on previousBalance (from last checkpoint), not remaining scheduled
    // balance. This is intentional: if no actor called release(), the accrued amount is likely
    // insignificant to searchers, so a higher threshold (favoring faster release) is acceptable.
    if (previousBalance > 0 && block.number < endReleaseBlock) {
      uint256 minBalanceForReset = (previousBalance * windowResetBps) / BPS;
      if (newDeposit < minBalanceForReset) {
        // Threshold not exceeded, add the tokens to the currently active drip.
        releaseWindow = uint16(endReleaseBlock - block.number);
      }
    }

    // If the remaining balance is less than the release window, immediately release the remaining
    // balance to skip dust accumulation
    if (postDripBalance < originalReleaseWindow) {
      releasedAmount += postDripBalance;
      postDripBalance = 0;
    }
  }
}
