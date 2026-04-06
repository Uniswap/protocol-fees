// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IMailbox} from "../interfaces/hyperlane/IMailbox.sol";

struct HyperlaneMessage {
    uint32 origin;
    address sender;
    bytes body;
    uint256 receivedAt;
}

contract HyperlaneReceiver {
    address public immutable MAILBOX;

    uint32 public constant BNB_DOMAIN_ID = 56;

    address public bnbSender;

    constructor(address mailbox) {
        MAILBOX = mailbox;
    }

    function handle(
        uint32 origin,
        bytes32 sender,
        bytes calldata body
    ) external payable {
        require(msg.sender == MAILBOX);
        require(origin == BNB_DOMAIN_ID);

        // ...
    }
}
