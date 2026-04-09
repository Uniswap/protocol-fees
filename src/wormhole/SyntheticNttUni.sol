// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Owned} from "solmate/src/auth/Owned.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {INttToken} from "../interfaces/wormhole/INttToken.sol";

/// @title Synthetic Ntt Uniswap Token
/// @notice This is a synthetic token which exists on foreign chains for the foreign Wormhole Native
///         Token Transfer (NTT) system to manage. The canonical UNI exists on Ethereum Layer 1
///         whereas the synthetic UNI exists on all foreign chains such that the respective NTT
///         system can mint and burn synthetic UNI to match the amount of canonical UNI locked in
///         the Ethereum Layer 1 deployment of the NTT system.
contract SyntheticNttUni is Owned, ERC20, INttToken {
    /// @notice Logged when the Wormhole Native Token Transfer address changes.
    /// @param ntt New Wormhole Native Token Transfer address.
    event NttSet(address indexed ntt);

    /// @notice Wormhole Native Token Transfer address.
    address public ntt;

    constructor(address initialNtt) Owned(msg.sender) ERC20("Synthetic Ntt Uniswap", "NUNI", 18) {
        ntt = initialNtt;
    }

    /// @notice Set the Wormhole Native Token Transfer address.
    /// @param newNtt New Wormhole Native Token Transfer address.
    function setNtt(address newNtt) public onlyOwner {
        ntt = newNtt;

        emit NttSet(newNtt);
    }

    /// @notice Mints synthetic tokens.
    /// @dev Caller MUST be Wormhole Native Token Transfer.
    /// @param receiver Account which receives the mint.
    /// @param amount Amount to mint.
    function mint(address receiver, uint256 amount) external {
        require(msg.sender == ntt);

        _mint(receiver, amount);
    }

    /// @notice Burns synthetic tokens from the caller.
    /// @dev Caller MUST be Wormhole Native Token Transfer.
    /// @param amount Amount to mint.
    function burn(uint256 amount) external {
        require(msg.sender == ntt);

        _burn(msg.sender, amount);
    }
}
