// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {SyntheticNttUni, ERC20} from "../../src/wormhole/SyntheticNttUni.sol";

// trapdooring through `mockMint` for test setups
contract MockSyntheticNttUni is SyntheticNttUni {
    function mockMint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}
