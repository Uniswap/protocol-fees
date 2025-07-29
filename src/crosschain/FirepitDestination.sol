// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Owned} from "solmate/auth/Owned.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IL1CrossDomainMessenger} from "../interfaces/IL1CrossDomainMessenger.sol";
import {AssetSink} from "../AssetSink.sol";
import {SoftNonce} from "../base/Nonce.sol";

error UnauthorizedCall();

/// @notice a contract for receiving crosschain messages. Validates messages and releases assets
/// from the AssetSink
contract FirepitDestination is SoftNonce, Owned {
  /// @notice the source contract that is allowed to originate messages to this contract i.e.
  /// FirepitSource
  /// @dev updatable by owner
  address public allowableSource;

  /// @notice the local contract(s) that are allowed to call this contract, i.e. Message Relayers
  /// @dev updatable by owner
  mapping(address callers => bool allowed) public allowableCallers;

  AssetSink public immutable ASSET_SINK;

  event FailedRelease(address indexed asset, address indexed claimer, bytes reason);

  constructor(address _owner, address _assetSink) Owned(_owner) {
    ASSET_SINK = AssetSink(_assetSink);
  }

  modifier onlyAllowed() {
    require(
      allowableCallers[msg.sender]
        && allowableSource == IL1CrossDomainMessenger(msg.sender).xDomainMessageSender(),
      UnauthorizedCall()
    );
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
    onlyAllowed
    checkDeadline(deadline)
    handleNonce(_nonce)
  {
    for (uint256 i; i < assets.length; i++) {
      try ASSET_SINK.release(assets[i], claimer) {}
      catch (bytes memory reason) {
        emit FailedRelease(Currency.unwrap(assets[i]), claimer, reason);
      }
    }
  }

  function setAllowableCallers(address callers, bool isAllowed) external onlyOwner {
    allowableCallers[callers] = isAllowed;
  }

  function setAllowableSource(address source) external onlyOwner {
    allowableSource = source;
  }
}
