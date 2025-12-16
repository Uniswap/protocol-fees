// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Script, console2} from "forge-std/Script.sol";
import {IAgreementAnchorFactory} from "dao-signer/src/interfaces/IAgreementAnchorFactory.sol";

contract CreateAgreementAnchors is Script {
  IAgreementAnchorFactory public constant AGREEMENT_ANCHOR_FACTORY =
    IAgreementAnchorFactory(0x5Ef3cCf9eC7E0af61E1767b2EEbB50e052b5Df47);

  bytes32 public constant AGREEMENT_ANCHOR_1_CONTENT_HASH =
    0xb7a5a04f613e49ce4a8c2fb142a37c6781bda05c62d46a782f36bb6e97068d3b;
  address public constant AGREEMENT_ANCHOR_1_COUNTER_SIGNER =
    0x7A36852A428513221555aeC720a09eCd83818310;
  bytes32 public constant AGREEMENT_ANCHOR_2_CONTENT_HASH =
    0xa4e0d81bb3af7544e6efcb37a5d38c96511c815274c8616176708c998d1761f1;
  address public constant AGREEMENT_ANCHOR_2_COUNTER_SIGNER =
    0xD1F55571cbB04139716a9a5076Aa69626B6df009;
  bytes32 public constant AGREEMENT_ANCHOR_3_CONTENT_HASH =
    0xdac83d28ab1675b69c7fea7f6eb6ee20d19893a426cd9a3e58b654330ac94429;
  address public constant AGREEMENT_ANCHOR_3_COUNTER_SIGNER =
    0x5018e04241D2739E65919fa9B4826C79044e13e2;

  function run() public returns (address, address, address) {
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
    address agreementAnchor3 = address(
      AGREEMENT_ANCHOR_FACTORY.createAgreementAnchor(
        AGREEMENT_ANCHOR_3_CONTENT_HASH, AGREEMENT_ANCHOR_3_COUNTER_SIGNER
      )
    );
    console2.log("Agreement Anchor 1:", agreementAnchor1);
    console2.log("Agreement Anchor 2:", agreementAnchor2);
    console2.log("Agreement Anchor 3:", agreementAnchor3);
    vm.stopBroadcast();
    return (agreementAnchor1, agreementAnchor2, agreementAnchor3);
  }
}
