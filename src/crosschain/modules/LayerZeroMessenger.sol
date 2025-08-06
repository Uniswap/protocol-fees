// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";

abstract contract OApp {
    function _lzSend() external;
    function combineOptions() external returns (bytes memory);
    function MessagingFee() external returns (uint256, uint256);
}

contract LayerZeroMessenger is OApp {
  address public immutable MESSENGER;
  address public immutable L2_TARGET;

  constructor(address _messenger, address _l2Target) {
    MESSENGER = _messenger;
    L2_TARGET = _l2Target;
  }

  function messageWormhole(
    uint256 destinationNonce,
    Currency[] memory assets,
    address claimer,
    uint32 l2GasLimit
  ) internal {
    // 3. Call OAppSender._lzSend to package and dispatch the cross-chain message
    //    - _dstEid:   remote chain's Endpoint ID
    //    - _message:  ABI-encoded string
    //    - _options:  combined execution options (enforced + caller-provided)
    //    - MessagingFee(msg.value, 0): pay all gas as native token; no ZRO
    //    - payable(msg.sender): refund excess gas to caller
    //
    //    combineOptions (from OAppOptionsType3) merges enforced options set by the contract owner
    //    with any additional execution options provided by the caller
    _lzSend(
        _dstEid,
        _message,
        combineOptions(_dstEid, SEND, _options),
        MessagingFee(msg.value, 0),
        payable(msg.sender)
    );
  }
}
