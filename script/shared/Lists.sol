// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {Vm} from "forge-std/Vm.sol";

import {HookFamilyAssignment} from "../../src/interfaces/IV4FeePolicy.sol";

/// @dev Foundry's cheatcode handle. forge-std only exposes it as a member of the contracts a
/// script inherits, so a library declares its own.
Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

/// @dev Two tokens whose aggregator-hook pools take the stable-stable fee instead of the aggregator
/// family default. Order does not matter; the script sorts before calling the policy.
struct Pair {
  address token0;
  address token1;
}

/// @dev Per-chain lists read from CSV files under `params/<chain>/`, so a new list is a file
/// replacement rather than a Solidity edit.
///
/// Each file starts with the header named below. Rows are read for the header's columns and any
/// further columns are ignored, so a symbol or note column is fine. Cells are trimmed, blank lines
/// are dropped, and Windows line endings are tolerated. A header-only file is an empty list.
library Lists {
  string constant STABLE_STABLE_PAIRS_HEADER = "token0,token1";
  string constant HOOK_FAMILIES_HEADER = "hook,familyId";

  function stableStablePairs(string memory path) internal view returns (Pair[] memory pairs) {
    string[][] memory rows = _rows(path, STABLE_STABLE_PAIRS_HEADER);
    pairs = new Pair[](rows.length);
    for (uint256 i; i < rows.length; i++) {
      pairs[i] = Pair({token0: vm.parseAddress(rows[i][0]), token1: vm.parseAddress(rows[i][1])});
    }
  }

  function hookFamilies(string memory path)
    internal
    view
    returns (HookFamilyAssignment[] memory assignments)
  {
    string[][] memory rows = _rows(path, HOOK_FAMILIES_HEADER);
    assignments = new HookFamilyAssignment[](rows.length);
    for (uint256 i; i < rows.length; i++) {
      uint256 familyId = vm.parseUint(rows[i][1]);
      require(familyId <= type(uint8).max, string.concat(path, ": familyId out of range"));
      assignments[i] =
        HookFamilyAssignment({hook: vm.parseAddress(rows[i][0]), familyId: uint8(familyId)});
    }
  }

  /// @dev Reads the file, checks that its header starts with the expected columns, and splits
  /// every non-blank line after it into cells.
  function _rows(string memory path, string memory header)
    private
    view
    returns (string[][] memory rows)
  {
    string[] memory lines = vm.split(vm.readFile(path), "\n");

    uint256 count;
    for (uint256 i; i < lines.length; i++) {
      string memory line = vm.trim(lines[i]);
      if (bytes(line).length > 0) lines[count++] = line;
    }

    require(count > 0, string.concat(path, ": expected header ", header));
    string[] memory expected = vm.split(header, ",");
    string[] memory found = _cells(lines[0], expected.length, path);
    for (uint256 j; j < expected.length; j++) {
      require(
        keccak256(bytes(found[j])) == keccak256(bytes(expected[j])),
        string.concat(path, ": expected header ", header)
      );
    }

    rows = new string[][](count - 1);
    for (uint256 i = 1; i < count; i++) {
      rows[i - 1] = _cells(lines[i], expected.length, path);
    }
  }

  /// @dev Splits one line into trimmed cells, requiring at least `columns` of them.
  function _cells(string memory line, uint256 columns, string memory path)
    private
    pure
    returns (string[] memory cells)
  {
    cells = vm.split(line, ",");
    require(cells.length >= columns, string.concat(path, ": short row ", line));
    for (uint256 j; j < cells.length; j++) {
      cells[j] = vm.trim(cells[j]);
    }
  }
}
