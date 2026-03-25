// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct ProposalAction {
  address target;
  uint256 value;
  string signature;
  bytes data;
}

using { toItems } for ProposalAction[];

function toItems(ProposalAction[] memory actions) pure returns (
  address[] memory targets,
  uint256[] memory values,
  string[] memory signatures,
  bytes[] memory datas
) {
  uint256 length = actions.length;

  targets = new address[](length);
  values = new uint256[](length);
  signatures = new string[](length);
  datas = new bytes[](length);

  for (uint256 i; i < length; i++) {
    targets[i] = actions[i].target;
    values[i] = actions[i].value;
    signatures[i] = actions[i].signature;
    datas[i] = actions[i].data;
  }
}