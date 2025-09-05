// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";

interface IOwned {
  function owner() external view returns (address);
  function transferOwnership(address newOwner) external;
}
