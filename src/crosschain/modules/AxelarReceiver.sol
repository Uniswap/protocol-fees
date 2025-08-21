// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {AxelarExecutable} from "axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
// import {UnifiedMessageReceiver} from "../UnifiedMessageReceiver.sol";

contract AxelarReceiver is AxelarExecutable {
  // UnifiedMessageReceiver public immutable unifiedMessageReceiver;

  constructor(address _gateway) AxelarExecutable(_gateway) {
    // unifiedMessageReceiver = UnifiedMessageReceiver(_unifiedMessageReceiver);
  }

  function _execute(
    bytes32 commandId,
    string calldata _sourceChain,
    string calldata _sourceAddress,
    bytes calldata _payload
  ) internal override {
    (uint256 nonce, Currency[] memory assets, address claimer) =
      abi.decode(_payload, (uint256, Currency[], address));

    // unifiedMessageReceiver.receiveMessage(nonce, assets, claimer);
  }
}
