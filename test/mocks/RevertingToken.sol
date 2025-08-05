// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract RevertingToken is MockERC20 {
  mapping(address from => bool reverts) public revertFrom;

  constructor(string memory _name, string memory _symbol, uint8 _decimals)
    MockERC20(_name, _symbol, _decimals)
  {}

  function setRevertFrom(address _from, bool reverts) external {
    revertFrom[_from] = reverts;
  }

  function transfer(address destination, uint256 amount) public override returns (bool) {
    if (revertFrom[msg.sender]) revert("RevertingToken: transfer reverted");
    return super.transfer(destination, amount); // Call to super to maintain the original behavior
  }
}
