// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract OOGToken is MockERC20 {
  uint256 counter;

  constructor(string memory _name, string memory _symbol, uint8 _decimals)
    MockERC20(_name, _symbol, _decimals)
  {}

  function transfer(address, uint256) public override returns (bool) {
    while (true) counter++;
    return true;
  }
}
