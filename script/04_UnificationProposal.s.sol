// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {AttestationRequestData, AttestationRequest, IEAS} from "eas-contracts/IEAS.sol";
import {Script} from "forge-std/Script.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {MainnetDeployer} from "./deployers/MainnetDeployer.sol";
import {IUniswapV2Factory} from "briefcase/protocols/v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV3Factory} from "briefcase/protocols/v3-core/interfaces/IUniswapV3Factory.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {AgreementAnchor} from "dao-signer/src/AgreementAnchor.sol";
import {AgreementResolver} from "dao-signer/src/AgreementResolver.sol";

struct ProposalAction {
  address target;
  uint256 value;
  string signature;
  bytes data;
}

contract UnificationProposal is Script, StdAssertions {
  // TODO: Fill in these values
  AgreementAnchor public constant AGREEMENT_ANCHOR_1 =
    AgreementAnchor(0x0000000000000000000000000000000000000000);
  AgreementAnchor public constant AGREEMENT_ANCHOR_2 =
    AgreementAnchor(0x0000000000000000000000000000000000000000);
  AgreementAnchor public constant AGREEMENT_ANCHOR_3 =
    AgreementAnchor(0x0000000000000000000000000000000000000000);
  string public constant PROPOSAL_DESCRIPTION = "";

  IGovernorBravo internal constant GOVERNOR_BRAVO =
    IGovernorBravo(0x408ED6354d4973f66138C91495F2f2FCbd8724C3);
  IERC20 UNI = IERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
  IUniswapV2Factory public V2_FACTORY =
    IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
  IUniswapV3Factory public constant V3_FACTORY =
    IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
  address public constant OLD_FEE_TO_SETTER = 0x18e433c7Bf8A2E1d0197CE5d8f9AFAda1A771360;

  // EAS Constants
  IEAS internal constant EAS = IEAS(0xA1207F3BBa224E2c9c3c6D5aF63D0eb1582Ce587);
  bytes32 public constant AGREEMENT_SCHEMA_UID =
    0x504f10498bcdb19d4960412dbade6fa1530b8eed65c319f15cbe20fadafe56bd;

  function setUp() public {}

  function run(MainnetDeployer deployer) public {
    vm.startBroadcast();
    ProposalAction[] memory actions = _run(deployer);
    console2.log("Calldata details:");
    for (uint256 i = 0; i < actions.length; i++) {
      ProposalAction memory action = actions[i];
      assertTrue(action.target != address(0));
      console2.log("Action #", i);
      console2.log("Target", action.target);
      console2.log("Value", action.value);
      console2.log("Signature");
      console2.log(action.signature);
      console2.log("Calldata", i);
      console2.logBytes(action.data);
      console2.log("--------------------------------");
    }

    console2.log("Description:");
    console2.log(PROPOSAL_DESCRIPTION);
    // Prepare GovernorBravo propose() parameters
    address[] memory targets = new address[](actions.length);
    uint256[] memory values = new uint256[](actions.length);
    string[] memory signatures = new string[](actions.length);
    bytes[] memory calldatas = new bytes[](actions.length);
    for (uint256 i = 0; i < actions.length; i++) {
      ProposalAction memory action = actions[i];
      targets[i] = action.target;
      values[i] = action.value;
      signatures[i] = action.signature;
      calldatas[i] = action.data;
    }

    bytes memory proposalCalldata = abi.encodeCall(
      IGovernorBravo.propose, (targets, values, signatures, calldatas, PROPOSAL_DESCRIPTION)
    );
    console2.log("GovernorBravo.propose() Calldata:");
    console2.logBytes(proposalCalldata);

    GOVERNOR_BRAVO.propose(targets, values, signatures, calldatas, PROPOSAL_DESCRIPTION);
    vm.stopBroadcast();
  }

  function runAnvil(MainnetDeployer deployer) public {
    vm.startBroadcast(V3_FACTORY.owner());
    ProposalAction[] memory actions = _run(deployer);
    for (uint256 i = 0; i < actions.length; i++) {
      ProposalAction memory action = actions[i];
      (bool success,) = action.target.call{value: action.value}(action.data);
      require(success, "Call failed");
    }
    vm.stopBroadcast();
  }

  function runPranked(MainnetDeployer deployer) public {
    vm.startPrank(V3_FACTORY.owner());
    ProposalAction[] memory actions = _run(deployer);
    for (uint256 i = 0; i < actions.length; i++) {
      ProposalAction memory action = actions[i];
      (bool success,) = action.target.call{value: action.value}(action.data);
      require(success, "Call failed");
    }
    vm.stopPrank();
  }

  function _run(MainnetDeployer deployer) public returns (ProposalAction[] memory actions) {
    address timelock = deployer.V3_FACTORY().owner();

    // --- Proposal Actions Setup ---
    actions = new ProposalAction[](8);

    // Burn 100M UNI
    actions[0] = ProposalAction({
      target: address(UNI),
      value: 0,
      signature: "",
      data: abi.encodeCall(UNI.transfer, (address(0xdead), 100_000_000 ether))
    });

    // Set the owner of the v3 factory to the configured fee controller
    actions[1] = ProposalAction({
      target: address(V3_FACTORY),
      value: 0,
      signature: "",
      data: abi.encodeCall(V3_FACTORY.setOwner, (address(deployer.V3_FEE_ADAPTER())))
    });

    // Update the v2 fee to setter to the timelock
    actions[2] = ProposalAction({
      target: address(OLD_FEE_TO_SETTER),
      value: 0,
      signature: "",
      data: abi.encodeCall(IFeeToSetter.setFeeToSetter, (timelock))
    });

    // Set the recipient of v2 protocol fees to the token jar
    actions[3] = ProposalAction({
      target: address(V2_FACTORY),
      value: 0,
      signature: "",
      data: abi.encodeCall(V2_FACTORY.setFeeTo, (address(deployer.TOKEN_JAR())))
    });

    // Approve two years of vesting to the UNIvester smart contract
    // UNI stays in treasury until vested and unvested UNI can be cancelled by setting approve back
    // to 0
    actions[4] = ProposalAction({
      target: address(UNI),
      value: 0,
      signature: "",
      data: abi.encodeCall(UNI.approve, (address(deployer.UNI_VESTING()), 40_000_000 ether))
    });

    // DAO attests to Agreement 1
    if (address(AGREEMENT_ANCHOR_1) != address(0)) {
      actions[5] = ProposalAction({
        target: address(EAS),
        value: 0,
        signature: "",
        data: abi.encodeCall(
          EAS.attest,
          (AttestationRequest({
              schema: AGREEMENT_SCHEMA_UID,
              data: AttestationRequestData({
                recipient: address(AGREEMENT_ANCHOR_1),
                expirationTime: 0,
                revocable: false,
                refUID: bytes32(0),
                data: abi.encode(AGREEMENT_ANCHOR_1.CONTENT_HASH()),
                value: 0
              })
            }))
        )
      });
    }

    // DAO attests to Agreement 2
    if (address(AGREEMENT_ANCHOR_2) != address(0)) {
      actions[6] = ProposalAction({
        target: address(EAS),
        value: 0,
        signature: "",
        data: abi.encodeCall(
          EAS.attest,
          (AttestationRequest({
              schema: AGREEMENT_SCHEMA_UID,
              data: AttestationRequestData({
                recipient: address(AGREEMENT_ANCHOR_2),
                expirationTime: 0,
                revocable: false,
                refUID: bytes32(0),
                data: abi.encode(AGREEMENT_ANCHOR_2.CONTENT_HASH()),
                value: 0
              })
            }))
        )
      });
    }

    // DAO attests to Agreement 3
    if (address(AGREEMENT_ANCHOR_3) != address(0)) {
      actions[7] = ProposalAction({
        target: address(EAS),
        value: 0,
        signature: "",
        data: abi.encodeCall(
          EAS.attest,
          (AttestationRequest({
              schema: AGREEMENT_SCHEMA_UID,
              data: AttestationRequestData({
                recipient: address(AGREEMENT_ANCHOR_3),
                expirationTime: 0,
                revocable: false,
                refUID: bytes32(0),
                data: abi.encode(AGREEMENT_ANCHOR_3.CONTENT_HASH()),
                value: 0
              })
            }))
        )
      });
    }
  }
}

// interface for:
// https://etherscan.io/address/0x18e433c7Bf8A2E1d0197CE5d8f9AFAda1A771360#code
// the current V2_FACTORY.feeToSetter()
interface IFeeToSetter {
  function setFeeToSetter(address) external;
}

interface IGovernorBravo {
  function propose(
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory description
  ) external returns (uint256);
}
