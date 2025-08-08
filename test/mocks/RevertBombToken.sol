// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract RevertBombToken is MockERC20 {
  error RevertBomb(bytes reason);

  bytes bigReason;

  mapping(address from => bool reverts) public revertFrom;

  constructor(string memory _name, string memory _symbol, uint8 _decimals)
    MockERC20(_name, _symbol, _decimals)
  {}

  function setBigReason(uint32 _length) public {
    bigReason = new bytes(_length);
    for (uint32 i; i < _length; i++) {
      bigReason[i] = "F";
    }
  }

  function transfer(address, uint256) public view override returns (bool) {
    revert RevertBomb(bigReason);
  }
}
