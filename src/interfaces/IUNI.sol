// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUNI is IERC20 {
  function minter() external view returns (address);
  function mintingAllowedAfter() external view returns (uint256);
  function mint(address dst, uint256 rawAmount) external;
  function setMinter(address minter) external;
  function minimumTimeBetweenMints() external view returns (uint32);
}
