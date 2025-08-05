// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";

interface IFirepitDestination {
  function claimTo(uint256 _nonce, Currency[] memory assets, address claimer) external;
}
