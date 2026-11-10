// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Call} from "govkit/types/Call.sol";
import {IWormholeSender} from "govkit/interfaces/bridges/IWormholeSender.sol";
import {SelectorHandler} from "govkit/bridges/decoders/SelectorHandler.sol";

using SelectorHandler for bytes;

/// @dev Test-side inverse of `encodeWormhole` in `script/proposal-7/ArcFees.s.sol`.
///
/// This is govkit's `WormholeDecoder.decode` with the Wormhole chain id returned as encoded
/// instead of mapped back to an EIP-155 chain id. govkit's mapping does not know Arc yet, so the
/// govkit decoder reverts on any Arc message. When Arc lands in govkit, `encodeWormhole` can
/// collapse to `WormholeEncoder.encode`, tests import `WormholeDecoder`, and this file can
/// be deleted.
library WormholeDecode {
  error SelectorMismatch();
  error LengthsMismatch();

  /// @dev Decodes a `sendMessage` call as produced by `encodeWormhole`.
  /// @param wormholeCall Proposal-ready call targeting the Wormhole sender.
  /// @return sourceSender Uniswap's WormholeSender contract on Ethereum.
  /// @return remoteReceiver Uniswap's WormholeReceiver contract on the remote chain.
  /// @return wormholeChainId Wormhole-defined chain id of the remote chain.
  /// @return value Call value.
  /// @return remoteCalls Calls to be run from the WormholeReceiver on the remote chain.
  function decode(Call memory wormholeCall)
    internal
    pure
    returns (
      address sourceSender,
      address remoteReceiver,
      uint16 wormholeChainId,
      uint256 value,
      Call[] memory remoteCalls
    )
  {
    require(
      wormholeCall.data.getSelector() == IWormholeSender.sendMessage.selector, SelectorMismatch()
    );

    (
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory datas,
      address receiver,
      uint16 decodedWormholeChainId
    ) = abi.decode(
      wormholeCall.data.stripSelector(), (address[], uint256[], bytes[], address, uint16)
    );

    uint256 length = targets.length;
    require(length == values.length && length == datas.length, LengthsMismatch());

    remoteCalls = new Call[](length);

    for (uint256 i; i < length; i++) {
      remoteCalls[i] = Call({target: targets[i], value: values[i], data: datas[i]});
    }

    sourceSender = wormholeCall.target;
    remoteReceiver = receiver;
    wormholeChainId = decodedWormholeChainId;
    value = wormholeCall.value;
  }
}
