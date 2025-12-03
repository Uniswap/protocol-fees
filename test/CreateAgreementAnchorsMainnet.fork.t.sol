// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CreateAgreementAnchors} from "script/03_CreateAgreementAnchorsMainnet.s.sol";

contract CreateAgreementAnchorsMainnetForkTest is Test {
  CreateAgreementAnchors public script;

  function setUp() public {
    vm.createSelectFork("mainnet");
    script = new CreateAgreementAnchors();
  }

  function test_RevertIf_wrongChainId() public {
    vm.chainId(31_337);
    vm.expectRevert("Not mainnet");
    script.run();
  }

  function test_createsAgreementAnchors() public {
    (address agreementAnchor1, address agreementAnchor2, address agreementAnchor3) = script.run();
    assertEq(
      IAgreementAnchor(agreementAnchor1).CONTENT_HASH(), script.AGREEMENT_ANCHOR_1_CONTENT_HASH()
    );
    assertEq(
      IAgreementAnchor(agreementAnchor2).CONTENT_HASH(), script.AGREEMENT_ANCHOR_2_CONTENT_HASH()
    );
    assertEq(
      IAgreementAnchor(agreementAnchor2).PARTY_B(), script.AGREEMENT_ANCHOR_1_COUNTER_SIGNER()
    );
    assertEq(
      IAgreementAnchor(agreementAnchor2).PARTY_B(), script.AGREEMENT_ANCHOR_2_COUNTER_SIGNER()
    );
    assertEq(
      IAgreementAnchor(agreementAnchor3).CONTENT_HASH(), script.AGREEMENT_ANCHOR_3_CONTENT_HASH()
    );
    assertEq(
      IAgreementAnchor(agreementAnchor3).PARTY_B(), script.AGREEMENT_ANCHOR_3_COUNTER_SIGNER()
    );
  }
}

interface IAgreementAnchor {
  function PARTY_A() external view returns (address);
  function PARTY_B() external view returns (address);
  function CONTENT_HASH() external view returns (bytes32);
}
