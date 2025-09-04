// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title UnsafeCurrencyLibrary
/// @dev A utility / wrapper library for unsafe/unchecked non-halting Currency transfers
library UnsafeCurrencyLibrary {
  function tryTransfer(Currency currency, address to, uint256 amount)
    internal
    returns (bool success)
  {
    if (currency.isAddressZero()) {
      assembly ("memory-safe") {
        // Transfer the ETH and do NOT revert if it fails.
        success := call(gas(), to, amount, 0, 0, 0, 0)
      }
    } else {
      IERC20 token = IERC20(Currency.unwrap(currency));
      success = SafeERC20.trySafeTransfer(token, to, amount);
    }
  }
}
