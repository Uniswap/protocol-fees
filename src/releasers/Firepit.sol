// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {IReleaser} from "../interfaces/IReleaser.sol";
import {ExchangeReleaser} from "./ExchangeReleaser.sol";

/// @title Firepit
/// @notice An ExchangeReleaser with recipient set to the burn address address(0xdead)
contract Firepit is ExchangeReleaser {
  constructor(address _resource, uint256 _threshold, address _tokenJar)
    ExchangeReleaser(_resource, _threshold, _tokenJar, address(0xdead))
  {}
}
