// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Script, console2} from "forge-std/Script.sol";
import {IAgreementAnchorFactory} from "dao-signer/src/interfaces/IAgreementAnchorFactory.sol";
import {AgreementAnchor} from "dao-signer/src/AgreementAnchor.sol";

contract CreateAgreementAnchors is Script {
  IAgreementAnchorFactory public constant AGREEMENT_ANCHOR_FACTORY =
    IAgreementAnchorFactory(0x5Ef3cCf9eC7E0af61E1767b2EEbB50e052b5Df47);

  // TODO: set content hashes and counterparty addresses for DUNI agreements
  bytes32 public constant AGREEMENT_ANCHOR_1_CONTENT_HASH = "";
  address public constant AGREEMENT_ANCHOR_1_COUNTER_SIGNER = address(0);
  bytes32 public constant AGREEMENT_ANCHOR_2_CONTENT_HASH = "";
  address public constant AGREEMENT_ANCHOR_2_COUNTER_SIGNER = address(0);

  function run() public returns (address, address) {
    require(block.chainid == 1, "Not mainnet");
    vm.startBroadcast();
    address agreementAnchor1 = address(
      AGREEMENT_ANCHOR_FACTORY.createAgreementAnchor(
        AGREEMENT_ANCHOR_1_CONTENT_HASH, AGREEMENT_ANCHOR_1_COUNTER_SIGNER
      )
    );

    address agreementAnchor2 = address(
      AGREEMENT_ANCHOR_FACTORY.createAgreementAnchor(
        AGREEMENT_ANCHOR_2_CONTENT_HASH, AGREEMENT_ANCHOR_2_COUNTER_SIGNER
      )
    );
    console2.log("Agreement Anchor 1:", agreementAnchor1);
    console2.log("Agreement Anchor 2:", agreementAnchor2);
    vm.stopBroadcast();
    return (agreementAnchor1, agreementAnchor2);
  }
}
