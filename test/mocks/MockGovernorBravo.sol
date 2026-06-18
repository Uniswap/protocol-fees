// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

contract MockGovernorBravo {
  event ProposeCall(address indexed target, uint256 value, string signature, bytes data);

  event Proposal(string description);

  uint256 public id = 0x43;

  function propose(
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory description
  ) external returns (uint256) {
    require(
      targets.length == values.length && targets.length == signatures.length
        && targets.length == calldatas.length,
      "invalid lengths"
    );

    emit Proposal(description);

    for (uint256 i; i < targets.length; i++) {
      emit ProposeCall(targets[i], values[i], signatures[i], calldatas[i]);
    }

    return id;
  }
}
