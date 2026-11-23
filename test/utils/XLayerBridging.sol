// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {vm} from "govkit/forge/Constants.sol";

import {IXLayerBridgeFull} from "../interfaces/IXLayerBridgeFull.sol";
import {IGlobalExitRootManagerL1} from "../interfaces/IGlobalExitRootManagerL1.sol";
import {IGlobalExitRootManagerL2} from "../interfaces/IGlobalExitRootManagerL2.sol";

/// @dev Ethereum's network ID in the unified bridge.
uint32 constant ETHEREUM_NETWORK_ID = 0;

/// @dev X Layer's network ID in the unified bridge.
uint32 constant XLAYER_NETWORK_ID = 3;

/// @dev The unified bridge on Ethereum, which escrows UNI bridged to X Layer. It has the same
/// address as the unified bridge on X Layer, `XLayer.TOKEN_BRIDGE`.
/// https://etherscan.io/address/0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe
address constant ETHEREUM_TOKEN_BRIDGE = 0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe;

/// @dev The storage slot of `_branch[0]` in the unified bridge, on Ethereum and on X Layer.
/// `DepositContractBase` declares `bytes32[32] _branch` and then `depositCount` after
/// OpenZeppelin's `Initializable` and `ReentrancyGuardUpgradeable`, which take slots 0 to 50, so
/// `_branch` takes slots 51 to 82 and `depositCount` slot 83.
uint256 constant BRANCH_SLOT = 51;

/// @dev The height of the unified bridge's exit trees and of the RollupManager's rollup exit tree.
uint256 constant EXIT_TREE_HEIGHT = 32;

/// @dev The bit a claim's `globalIndex` sets when the deposit it claims was made on Ethereum. The
/// low 32 bits then hold the deposit's index in Ethereum's exit tree.
uint256 constant GLOBAL_INDEX_MAINNET_FLAG = 1 << 64;

/// @dev X Layer's index in the RollupManager's rollup exit tree: its rollup ID, which equals its
/// network ID, less one. A claim of a deposit made on X Layer puts it in bits 32 to 63 of
/// `globalIndex`.
uint32 constant XLAYER_ROLLUP_INDEX = XLAYER_NETWORK_ID - 1;

/// @dev A leaf a unified bridge appends to its local exit tree for a deposit, with the leaf's
/// merkle proof.
struct ExitLeaf {
  uint32 index;
  bytes32[32] proof;
}

/// @dev The arguments of a claim of a deposit of Ethereum UNI that vary between claims, and the
/// bridge the claim is submitted to.
struct UniClaim {
  address bridge;
  uint256 globalIndex;
  bytes32[32] localExitRootProof;
  bytes32[32] rollupExitRootProof;
  bytes32 mainnetExitRoot;
  bytes32 rollupExitRoot;
  uint32 destinationNetwork;
  address destinationAddress;
  uint256 amount;
}

/// @dev A deposit of UNI in the Ethereum unified bridge, with what a claim of it on X Layer needs.
struct UniDeposit {
  address recipient;
  uint256 amount;
  ExitLeaf leaf;
  bytes32 mainnetExitRoot;
  bytes32 rollupExitRoot;
}

/// @dev Returns the leaf `bridge` will append to its local exit tree for its next deposit, with the
/// leaf's merkle proof. Reads `bridge` on the selected fork.
function nextExitLeaf(address bridge) view returns (ExitLeaf memory leaf) {
  // The bridge appends the next deposit's leaf at index `depositCount`, so every subtree to the
  // leaf's right is empty. At each height where the index has a 1 bit, the leaf's sibling is the
  // full subtree to its left, whose root the bridge keeps in `_branch`. At every other height, the
  // sibling is the root of an empty subtree of that height.
  leaf.index = uint32(IXLayerBridgeFull(bridge).depositCount());
  bytes32 emptySubtreeRoot;
  for (uint256 height; height < EXIT_TREE_HEIGHT; height++) {
    leaf.proof[height] = (leaf.index >> height) & 1 == 1
      ? vm.load(bridge, bytes32(BRANCH_SLOT + height))
      : emptySubtreeRoot;
    emptySubtreeRoot = keccak256(abi.encodePacked(emptySubtreeRoot, emptySubtreeRoot));
  }
}

/// @dev Returns the root of the exit tree whose first leaves are `leaves` and whose other leaves
/// are empty, with the merkle proof of leaf `index`.
function merkleRootAndProof(bytes32[] memory leaves, uint256 index)
  pure
  returns (bytes32 root, bytes32[32] memory proof)
{
  bytes32[] memory nodes = leaves;
  bytes32 emptySubtreeRoot;
  for (uint256 height; height < EXIT_TREE_HEIGHT; height++) {
    // Take the sibling of the node on the proof's path, which is empty past the last node.
    uint256 sibling = index ^ 1;
    proof[height] = sibling < nodes.length ? nodes[sibling] : emptySubtreeRoot;

    // Hash each pair of nodes into the level above, pairing an odd last node with an empty
    // subtree.
    bytes32[] memory parents = new bytes32[]((nodes.length + 1) / 2);
    for (uint256 i; i < parents.length; i++) {
      bytes32 right = 2 * i + 1 < nodes.length ? nodes[2 * i + 1] : emptySubtreeRoot;
      parents[i] = keccak256(abi.encodePacked(nodes[2 * i], right));
    }
    nodes = parents;
    index >>= 1;
    emptySubtreeRoot = keccak256(abi.encodePacked(emptySubtreeRoot, emptySubtreeRoot));
  }
  root = nodes[0];
}

/// @dev Returns the global exit root of `mainnetExitRoot` and `rollupExitRoot`, computed as the
/// unified bridge computes it.
function globalExitRoot(bytes32 mainnetExitRoot, bytes32 rollupExitRoot) pure returns (bytes32) {
  return keccak256(abi.encodePacked(mainnetExitRoot, rollupExitRoot));
}

/// @dev Returns the global exit root manager of the unified bridge on Ethereum. Reads the bridge on
/// the selected fork, which must be the Ethereum fork.
function ethereumExitRootManager() view returns (IGlobalExitRootManagerL1) {
  return IGlobalExitRootManagerL1(IXLayerBridgeFull(ETHEREUM_TOKEN_BRIDGE).globalExitRootManager());
}

/// @dev Returns the global exit root manager of the unified bridge `bridge` on X Layer. Reads
/// `bridge` on the selected fork, which must be the X Layer fork.
function xLayerExitRootManager(address bridge) view returns (IGlobalExitRootManagerL2) {
  return IGlobalExitRootManagerL2(IXLayerBridgeFull(bridge).globalExitRootManager());
}

/// @dev Returns the metadata the unified bridge encodes into a deposit of Ethereum UNI or of its
/// wrapped UNI: the name, symbol and decimals.
function uniMetadata() pure returns (bytes memory) {
  return abi.encode("Uniswap", "UNI", uint8(18));
}
