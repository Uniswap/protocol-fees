// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {buildMaintenanceProposal} from "../script/proposal-5/MaintenanceProposal.s.sol";
import {MockGovernorBravo} from "./mocks/MockGovernorBravo.sol";

import {Uniswap} from "govkit/types/Uniswap.sol";
import {Proposal} from "govkit/types/Proposal.sol";
import {IGovernorBravo} from "govkit/interfaces/IGovernorBravo.sol";
import {Test} from "forge-std/Test.sol";

contract MaintenancenProposalTest is Test {
  Uniswap internal uniswap;
  IGovernorBravo internal governor;

  function setUp() external {
    uniswap.loadLatest();

    governor = IGovernorBravo(address(new MockGovernorBravo()));
  }

  function testPropose() external {
    Proposal memory prop = buildMaintenanceProposal(uniswap);

    (
      address[] memory targets,
      uint256[] memory values,
      string[] memory signatures,
      bytes[] memory datas,
      string memory description
    ) = prop.toGovernorBravoInputs();

    vm.expectEmit(true, true, true, true, address(governor));
    emit MockGovernorBravo.Proposal(prop.description);

    for (uint256 i; i < targets.length; i++) {
      vm.expectEmit(true, true, true, true, address(governor));
      emit MockGovernorBravo.ProposeCall(
        prop.calls[i].target, prop.calls[i].value, "", prop.calls[i].data
      );
    }

    governor.propose(targets, values, signatures, datas, description);
  }
}
