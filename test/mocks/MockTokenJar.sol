// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {ITokenJar, Currency} from "../../src/interfaces/ITokenJar.sol";

contract MockTokenJar is ITokenJar {
    event MockRelease(address indexed caller, address indexed recipient, Currency[] assets);

    address public releaser;

    bool public mockShouldThrow;

    function setReleaser(address _releaser) external {
        releaser = _releaser;
    }

    function release(Currency[] calldata assets, address recipient) external {
        // mocking this logic is out of scope for testing releaser implementations as this refers to
        // no state on the releaser contract
        //
        // we only add a throw case in the event the `recipient` address cannot receive one of the
        // asset transfers.
        require(!mockShouldThrow);

        emit MockRelease(msg.sender, recipient, assets);
    }

    function mockSetShouldThrow(bool newMockShouldThrow) external {
        mockShouldThrow = newMockShouldThrow;
    }
}
