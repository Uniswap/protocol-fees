// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/StdAssertions.sol";
import {MainnetDeployer} from "./deployers/MainnetDeployer.sol";
import {IUniswapV2Factory} from "briefcase/protocols/v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV3Factory} from "briefcase/protocols/v3-core/interfaces/IUniswapV3Factory.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract UnificationProposal is Script, StdAssertions {
  // TODO: Fill in these values
  address public constant AGREEMENT_ANCHOR_1 = address(0);
  bytes32 public constant CONTENT_HASH_1 = bytes32(0);
  address public constant AGREEMENT_ANCHOR_2 = address(0);
  bytes32 public constant CONTENT_HASH_2 = bytes32(0);
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
    (
      address[] memory targets,
      uint256[] memory values,
      string[] memory signatures,
      bytes[] memory calldatas
    ) = _run(deployer);
    console.log("Calldata details:");
    for (uint256 i = 0; i < calldatas.length; i++) {
      assertTrue(targets[i] != address(0));
      console.log("Target", i);
      console.log(targets[i]);
      console.log("Value", i);
      console.log(values[i]);
      console.log("Signature", i);
      console.log(signatures[i]);
      console.log("Calldata", i);
      console.logBytes(calldatas[i]);
      console.log("--------------------------------");
    }

    console.log("Description:");
    console.log(PROPOSAL_DESCRIPTION);

    bytes memory proposalCalldata = abi.encodeCall(
      IGovernorBravo.propose, (targets, values, signatures, calldatas, PROPOSAL_DESCRIPTION)
    );
    console.log("GovernorBravo.propose() Calldata:");
    console.logBytes(proposalCalldata);

    GOVERNOR_BRAVO.propose(targets, values, signatures, calldatas, PROPOSAL_DESCRIPTION);
    vm.stopBroadcast();
  }

  function runAnvil(MainnetDeployer deployer) public {
    vm.startBroadcast(V3_FACTORY.owner());
    _run(deployer);
    vm.stopBroadcast();
  }

  function runPranked(MainnetDeployer deployer) public {
    vm.startPrank(V3_FACTORY.owner());
    (
      address[] memory targets,
      uint256[] memory values,
      string[] memory signatures,
      bytes[] memory calldatas
    ) = _run(deployer);
    for (uint256 i = 0; i < targets.length; i++) {
      targets[i].call{value: values[i]}(calldatas[i]);
    }
    vm.stopPrank();
  }

  function _run(MainnetDeployer deployer)
    public
    returns (
      address[] memory targets,
      uint256[] memory values,
      string[] memory signatures,
      bytes[] memory calldatas
    )
  {
    address timelock = deployer.V3_FACTORY().owner();

    // --- Proposal Actions Setup ---
    address[] memory targets = new address[](7);
    uint256[] memory values = new uint256[](7);
    string[] memory signatures = new string[](7);
    bytes[] memory calldatas = new bytes[](7);

    // Burn 100M UNI
    targets[0] = address(UNI);
    values[0] = 0;
    signatures[0] = "";
    calldatas[0] = abi.encodeCall(UNI.transfer, (address(0xdead), 100_000_000 ether));

    // Set the owner of the v3 factory to the configured fee controller
    targets[1] = address(V3_FACTORY);
    values[1] = 0;
    signatures[1] = "";
    calldatas[1] = abi.encodeCall(V3_FACTORY.setOwner, (address(deployer.V3_FEE_ADAPTER())));

    // Update the v2 fee to setter to the timelock
    targets[2] = address(OLD_FEE_TO_SETTER);
    values[2] = 0;
    signatures[2] = "";
    calldatas[2] = abi.encodeCall(IFeeToSetter.setFeeToSetter, (timelock));

    // Set the recipient of v2 protocol fees to the token jar
    targets[3] = address(V2_FACTORY);
    values[3] = 0;
    signatures[3] = "";
    calldatas[3] = abi.encodeCall(V2_FACTORY.setFeeTo, (address(deployer.TOKEN_JAR())));

    // Approve two years of vesting to the UNIvester smart contract
    // UNI stays in treasury until vested and unvested UNI can be cancelled by setting approve back
    // to 0
    targets[4] = address(UNI);
    values[4] = 0;
    signatures[4] = "";
    calldatas[4] = abi.encodeCall(UNI.approve, (address(deployer.UNI_VESTING()), 40_000_000 ether));

    // DAO attests to Agreement 1
    if (AGREEMENT_ANCHOR_1 != address(0)) {
      assertEq(CONTENT_HASH_1, IAgreementAnchor(AGREEMENT_ANCHOR_1).CONTENT_HASH());
      targets[5] = address(EAS);
      values[5] = 0;
      signatures[5] = "";
      calldatas[5] = abi.encodeCall(
        EAS.attest,
        (AttestationRequest({
            schema: AGREEMENT_SCHEMA_UID,
            data: AttestationRequestData({
              recipient: AGREEMENT_ANCHOR_1,
              expirationTime: 0,
              revocable: false,
              refUID: bytes32(0),
              data: abi.encode(CONTENT_HASH_1),
              value: 0
            })
          }))
      );
    }

    // DAO attests to Agreement 2
    if (AGREEMENT_ANCHOR_2 != address(0)) {
      assertEq(CONTENT_HASH_2, IAgreementAnchor(AGREEMENT_ANCHOR_2).CONTENT_HASH());
      targets[6] = address(EAS);
      values[6] = 0;
      signatures[6] = "";
      calldatas[6] = abi.encodeCall(
        EAS.attest,
        (AttestationRequest({
            schema: AGREEMENT_SCHEMA_UID,
            data: AttestationRequestData({
              recipient: AGREEMENT_ANCHOR_2,
              expirationTime: 0,
              revocable: false,
              refUID: bytes32(0),
              data: abi.encode(CONTENT_HASH_2),
              value: 0
            })
          }))
      );
    }

    return (targets, values, signatures, calldatas);
  }
}

// interface for:
// https://etherscan.io/address/0x18e433c7Bf8A2E1d0197CE5d8f9AFAda1A771360#code
// the current V2_FACTORY.feeToSetter()
interface IFeeToSetter {
  function setFeeToSetter(address) external;
}

struct AttestationRequestData {
  address recipient;
  uint64 expirationTime;
  bool revocable;
  bytes32 refUID;
  bytes data;
  uint256 value;
}

struct AttestationRequest {
  bytes32 schema;
  AttestationRequestData data;
}

interface IEAS {
  function attest(AttestationRequest calldata request) external payable returns (bytes32);
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

interface IAgreementAnchor {
  function CONTENT_HASH() external returns (bytes32);
}
