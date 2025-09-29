// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Owned} from "solmate/src/auth/Owned.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IL1CrossDomainMessenger} from "../interfaces/IL1CrossDomainMessenger.sol";
import {AssetSink} from "../AssetSink.sol";
import {Nonce} from "../base/Nonce.sol";

error UnauthorizedCall();

/// @notice a contract for receiving crosschain messages. Validates messages and releases assets
/// from the AssetSink
contract FirepitDestination is Nonce, Owned {
  /// @notice the source contract that is allowed to originate messages to this contract i.e.
  /// FirepitSource
  /// @dev updatable by owner
  address public allowableSource;

  /// @notice the local contract(s) that are allowed to call this contract, i.e. Message Relayers
  /// @dev updatable by owner
  mapping(address callers => bool allowed) public allowableCallers;

  AssetSink public immutable ASSET_SINK;
  uint256 public constant MINIMUM_RELEASE_GAS = 100_000;

  event FailedRelease(uint256 indexed _nonce, address indexed _claimer);

  constructor(address _owner, address _assetSink) Owned(_owner) {
    ASSET_SINK = AssetSink(payable(_assetSink));
  }

  modifier onlyAllowed() {
    require(
      allowableCallers[msg.sender]
        && allowableSource == IL1CrossDomainMessenger(msg.sender).xDomainMessageSender(),
      UnauthorizedCall()
    );
    _;
  }

  /// @notice Calls Asset Sink to release assets to a destination
  /// @dev only callable by the messenger via the authorized L1 source contract
  function claimTo(uint256 _nonce, Currency[] calldata assets, address claimer)
    external
    onlyAllowed
    handleNonce(_nonce)
  {
    if (gasleft() < MINIMUM_RELEASE_GAS) {
      emit FailedRelease(_nonce, claimer);
      return;
    }
    try ASSET_SINK.release(assets, claimer) {}
    catch {
      emit FailedRelease(_nonce, claimer);
      return;
    }
  }

  function setAllowableCallers(address callers, bool isAllowed) external onlyOwner {
    allowableCallers[callers] = isAllowed;
  }

  function setAllowableSource(address source) external onlyOwner {
    allowableSource = source;
  }
}
