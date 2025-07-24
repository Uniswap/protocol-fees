// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Owned} from "solmate/auth/Owned.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IL1CrossDomainMessenger} from "../interfaces/IL1CrossDomainMessenger.sol";
import {AssetSink} from "../AssetSink.sol";
import {Nonce} from "../base/Nonce.sol";

/// @notice a contract for receiving crosschain messages. Validates messages and releases assets
/// from the AssetSink
contract FirepitDestination is Nonce, Owned {
  AssetSink public immutable ASSET_SINK;
  IL1CrossDomainMessenger public immutable MESSENGER;

  /// @notice the L1 contract address FirepitSource
  mapping(address source => bool allowed) public allowableSources;

  constructor(address _owner, address _assetSink, address _messenger) Owned(_owner) {
    ASSET_SINK = AssetSink(_assetSink);
    MESSENGER = IL1CrossDomainMessenger(_messenger);
  }

  modifier onlyMessengerAndFirepitSource() {
    require(msg.sender == address(MESSENGER) && allowableSources[MESSENGER.xDomainMessageSender()]);
    _;
  }

  modifier checkDeadline(uint256 timestamp) {
    require(block.timestamp <= timestamp);
    _;
  }

  /// @notice Calls Asset Sink to release assets to a destination
  /// @dev only callable by the messenger via the authorized L1 source contract
  /// @dev reverts when the message exceeds the deadline
  function claimTo(uint256 _nonce, Currency[] memory assets, address claimer, uint256 deadline)
    external
    onlyMessengerAndFirepitSource
    checkDeadline(deadline)
    handleNonce(_nonce)
  {
    for (uint256 i; i < assets.length; i++) {
      ASSET_SINK.release(assets[i], claimer);
    }
  }

  function setAllowableSource(address source, bool isAllowed) external onlyOwner {
    allowableSources[source] = isAllowed;
  }
}
