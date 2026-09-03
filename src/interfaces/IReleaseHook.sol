// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

interface IReleaseHook {
    function RELEASER() external view returns (address);

    function afterRelease(address resource, uint256 threshold) external payable;
}
