// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

interface INttToken {
    function mint(address account, uint256 amount) external;
    function burn(uint256 amount) external;
}
