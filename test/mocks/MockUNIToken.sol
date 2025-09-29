pragma solidity ^0.8.29;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Owned} from "solmate/src/auth/Owned.sol";

contract MockUNIToken is ERC20 {
  /// @notice Total number of tokens in circulation
  uint256 public constant initialTotalSupply = 1_000_000_000e18; // 1 billion Uni

  /// @notice Address which may mint new tokens
  address public minter;

  /// @notice The timestamp after which minting may occur
  uint256 public mintingAllowedAfter;

  /// @notice Minimum time between mints
  uint32 public constant minimumTimeBetweenMints = 1 days * 365;

  /// @notice Cap on the percentage of totalSupply that can be minted at each mint
  uint8 public constant mintCap = 2;

  /// @notice An event thats emitted when the minter address is changed
  event MinterChanged(address minter, address newMinter);

  error NotMinter();
  error MintingNotReady();
  error InvalidRecipient();
  error MintCap();

  constructor() ERC20("Uniswap", "UNI", 18) {
    _mint(msg.sender, initialTotalSupply);
    minter = msg.sender;
    mintingAllowedAfter = block.timestamp + minimumTimeBetweenMints;
    emit MinterChanged(address(0), minter);
  }

  /**
   * @notice Change the minter address
   * @param minter_ The address of the new minter
   */
  function setMinter(address minter_) external {
    if (msg.sender != minter) revert NotMinter();
    emit MinterChanged(minter, minter_);
    minter = minter_;
  }

  /**
   * @notice Mint new tokens
   * @param dst The address of the destination account
   * @param amount The number of tokens to be minted
   */
  function mint(address dst, uint256 amount) external {
    if (msg.sender != minter) revert NotMinter();
    if (block.timestamp < mintingAllowedAfter) revert MintingNotReady();
    if (dst == address(0)) revert InvalidRecipient();

    // record the mint
    mintingAllowedAfter = block.timestamp + minimumTimeBetweenMints;

    // mint the amount
    if (amount > totalSupply * mintCap / 100) revert MintCap();
    _mint(dst, amount);
  }
}
