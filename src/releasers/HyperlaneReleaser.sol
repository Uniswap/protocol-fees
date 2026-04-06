// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ExchangeReleaser} from "./ExchangeReleaser.sol";
import {ResourceManager} from "../base/ResourceManager.sol";
import {Nonce} from "../base/Nonce.sol";
import {ITokenJar} from "../interfaces/ITokenJar.sol";
import {IReleaser} from "../interfaces/IReleaser.sol";
import {IMailbox} from "../interfaces/hyperlane/IMailbox.sol";
import {IMessageRecipient} from "../interfaces/hyperlane/IMessageRecipient.sol";

/// @title HyperlaneBridgedResourceFirepit
// TODO: we need better names for this.
contract HyperlaneBridgedResourceFirepit is IReleaser, ResourceManager, Nonce {
    using SafeTransferLib for ERC20;

    error ZeroAddress();

    address public immutable MAILBOX;

    uint32 public constant ETHEREUM_DOMAIN_ID = 1;

    address public ethereumReceiver;

    /// @notice Maximum number of different assets that can be released in a single call
    uint256 public constant MAX_RELEASE_LENGTH = 20;

    /// @inheritdoc IReleaser
    ITokenJar public immutable TOKEN_JAR;

    /// @dev The L1 UNI token address (Ethereum mainnet)
    address public immutable L1_RESOURCE;

    address internal constant BURN_ADDRESS = address(0xdead);

    bool internal locked;

    modifier nonReentrant() {
        require(!locked);
        locked = true;
        _;
        locked = false;
    }

    /// @notice Creates a new ExchangeReleaser instance
    /// @param _resource The address of the resource token that must be transferred
    /// @param _threshold The minimum amount of resource tokens that must be transferred
    /// @param _tokenJar The address of the TokenJar contract holding the assets
    /// @param _recipient The address that will receive the resource tokens
    constructor(
        address _resource,
        address _l1Resource,
        uint256 _threshold,
        address _tokenJar,
        address _recipient,
        address _mailbox
    ) ResourceManager(_resource, _threshold, msg.sender, _recipient) {
        TOKEN_JAR = ITokenJar(payable(_tokenJar));
        L1_RESOURCE = _l1Resource;
        MAILBOX = _mailbox;
    }

    function quoteMsgFee(bytes memory _body) public view returns (uint256) {
        return IMailbox(MAILBOX).quoteDispatch(
            ETHEREUM_DOMAIN_ID,
            bytes32(uint256(uint160(ethereumReceiver))),
            _body
        );
    }

    /// @inheritdoc IReleaser
    function release(
        uint256 _nonce,
        Currency[] calldata assets,
        address recipient
    ) external handleNonce(_nonce) nonReentrant {
        require(assets.length <= MAX_RELEASE_LENGTH, TooManyAssets());
        RESOURCE.safeTransferFrom(msg.sender, RESOURCE_RECIPIENT, threshold);
        TOKEN_JAR.release(assets, recipient);
        emit Released(_nonce, recipient, assets);

        _afterRelease(assets, recipient);
    }

    /// @notice Hook called after assets are released. Invokes the Wormhole wrapped transfer token
    /// bridge.
    function _afterRelease(Currency[] calldata, address) internal {
        bytes memory _body;

        uint256 fee = quoteMsgFee(_body);

        require(msg.value >= fee);

        IMailbox(MAILBOX).dispatch{value: fee}(
            ETHEREUM_DOMAIN_ID,
            bytes32(uint256(uint160(ethereumReceiver))),
            _body
        );

        uint256 refund = msg.value - fee;

        if (refund > 0) {
            (bool ok, ) = msg.sender.call{value: refund}(new bytes(0));

            require(ok);
        }
    }

    receive() external payable {}
}
