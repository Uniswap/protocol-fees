// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

/// @title V4FeeController
/// @notice Triggers the collection of protocol fees to a predefined fee sink.
/// TODO: Add functionality for setting fees.
contract V4FeeController {
  /// @notice Thrown when the amount collected is less than the amount expected.
  error AmountCollectedTooLow(uint256 amountCollected, uint256 amountExpected);

  IPoolManager public immutable POOL_MANAGER;

  address public feeSink;

  constructor(address _poolManager, address _feeSink) {
    POOL_MANAGER = IPoolManager(_poolManager);
    feeSink = _feeSink;
  }

  /// @notice Collects the protocol fees for the given currencies to the fee sink.
  /// @param currency The currencies to collect fees for.
  /// @param amountRequested The amount of each currency to request.
  /// @param amountExpected The amount of each currency that is expected to be collected.
  function collect(
    Currency[] memory currency,
    uint256[] memory amountRequested,
    uint256[] memory amountExpected
  ) external {
    uint256 amountCollected;
    for (uint256 i = 0; i < currency.length; i++) {
      uint256 _amountRequested = amountRequested[i];
      uint256 _amountExpected = amountExpected[i];

      amountCollected = POOL_MANAGER.collectProtocolFees(feeSink, currency[i], _amountRequested);
      if (amountCollected < _amountExpected) {
        revert AmountCollectedTooLow(amountCollected, _amountExpected);
      }
    }
  }
}
