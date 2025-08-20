// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Owned} from "solmate/src/auth/Owned.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {AssetSink} from "../AssetSink.sol";
import {Nonce} from "../base/Nonce.sol";

error UnauthorizedCall();

/// @notice a contract for receiving crosschain messages. Validates messages and releases assets
/// from the AssetSink
contract FirepitDestination is Nonce, Owned {
  /// @notice The unified messaging bridge that can call this contract
  /// @dev updatable by owner
  address public allowableCaller;

  AssetSink public immutable ASSET_SINK;
  uint256 public constant MINIMUM_RELEASE_GAS = 100_000;
  uint256 public constant REMAINDER_GAS = 10_000;

  event FailedRelease(address indexed asset, address indexed claimer);

  constructor(address _owner, address _assetSink, address _allowableCaller) Owned(_owner) {
    ASSET_SINK = AssetSink(payable(_assetSink));
    allowableCaller = _allowableCaller;
  }

  modifier onlyAllowed() {
    require(msg.sender == allowableCaller, UnauthorizedCall());
    _;
  }

  /// @notice Calls Asset Sink to release assets to a destination
  /// @dev only callable by the messenger via the authorized L1 source contract
  function claimTo(uint256 _nonce, Currency[] memory assets, address claimer)
    external
    onlyAllowed
    handleNonce(_nonce)
  {
    for (uint256 i; i < assets.length; i++) {
      if (gasleft() < MINIMUM_RELEASE_GAS) {
        emit FailedRelease(Currency.unwrap(assets[i]), claimer);
        return;
      }

      // equivalent to, but limit the return data to 0
      // try ASSET_SINK.release{gas: gasleft() - REMAINDER_GAS}(assets[i], claimer) {}
      // catch {
      //   emit FailedRelease(Currency.unwrap(assets[i]), claimer);
      // }
      bytes memory callData = abi.encodeWithSelector(AssetSink.release.selector, assets[i], claimer);
      bool success;
      address target = address(ASSET_SINK);
      assembly {
        success :=
          call(sub(gas(), REMAINDER_GAS), target, 0, add(callData, 0x20), mload(callData), 0, 0)
      }
      if (!success) emit FailedRelease(Currency.unwrap(assets[i]), claimer);
    }
  }

  function setAllowableCaller(address _newAllowableCaller) external onlyOwner {
    allowableCaller = _newAllowableCaller;
  }
}
