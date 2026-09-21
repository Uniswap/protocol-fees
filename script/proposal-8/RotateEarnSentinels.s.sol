// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";

import {Uniswap} from "govkit/types/Uniswap.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {Proposal} from "govkit/types/Proposal.sol";
import {Call, LibCall} from "govkit/types/Call.sol";
import {GovernanceSeatbelt} from "govkit/forge/GovernanceSeatbelt.sol";

import {Earn, Sentinels, smokeCheck} from "./Constants.sol";
import {IVaultV2} from "./Interfaces.sol";
import {DESCRIPTION} from "./Description.sol";

// Adding a sentinel is a `true` flag, removing a sentinel is a `false` flag.
bool constant ADD = true;
bool constant REMOVE = false;

/// @dev The proposal's calls. A free function so the fork test, and anything outside this repo,
///      builds the same calls the script writes without deploying the script. Takes the govkit
///      address book for uniformity with other proposals; this one reads only `Earn` constants.
function buildProposal(Uniswap storage) pure returns (Proposal memory) {
  smokeCheck();

  // ---------------------------------------------------------------------------------------------
  // 00: Add new sentinel to uniUSDC
  //
  Call memory addUniUSDCSentinel = Call({
    target: Earn.UNI_USDC,
    value: 0,
    data: abi.encodeCall(IVaultV2.setIsSentinel, (Sentinels.UNI_USDC_NEW, ADD))
  });

  // ---------------------------------------------------------------------------------------------
  // 01: Remove legacy sentinel from uniUSDC
  //
  Call memory removeUniUSDCSentinel = Call({
    target: Earn.UNI_USDC,
    value: 0,
    data: abi.encodeCall(IVaultV2.setIsSentinel, (Sentinels.UNI_USDC_LEGACY, REMOVE))
  });

  // ---------------------------------------------------------------------------------------------
  // 02: Add new sentinel to uniUSDT
  //
  Call memory addUniUSDTSentinel = Call({
    target: Earn.UNI_USDT,
    value: 0,
    data: abi.encodeCall(IVaultV2.setIsSentinel, (Sentinels.UNI_USDT_NEW, ADD))
  });

  // ---------------------------------------------------------------------------------------------
  // 03: Remove legacy sentinel from uniUSDT
  //
  Call memory removeUniUSDTSentinel = Call({
    target: Earn.UNI_USDT,
    value: 0,
    data: abi.encodeCall(IVaultV2.setIsSentinel, (Sentinels.UNI_USDT_LEGACY, REMOVE))
  });

  // ---------------------------------------------------------------------------------------------
  // 04: Add new sentinel to uniETH
  //
  Call memory addUniETHSentinel = Call({
    target: Earn.UNI_ETH,
    value: 0,
    data: abi.encodeCall(IVaultV2.setIsSentinel, (Sentinels.UNI_ETH_NEW, ADD))
  });

  // ---------------------------------------------------------------------------------------------
  // 05: Remove legacy sentinel from uniETH
  //
  Call memory removeUniETHSentinel = Call({
    target: Earn.UNI_ETH,
    value: 0,
    data: abi.encodeCall(IVaultV2.setIsSentinel, (Sentinels.UNI_ETH_LEGACY, REMOVE))
  });

  return Proposal({
    description: DESCRIPTION,
    calls: LibCall.newCalls(
      [
        addUniUSDCSentinel,
        removeUniUSDCSentinel,
        addUniUSDTSentinel,
        removeUniUSDTSentinel,
        addUniETHSentinel,
        removeUniETHSentinel
      ]
    )
  });
}

contract RotateEarnSentinels is Script {
  Uniswap internal uniswap;

  constructor() {
    uniswap.loadLatest();
  }

  /// @dev Asserts the state the proposal depends on, then writes it for Governance Seatbelt.
  ///      Run against Ethereum: `forge script ... --rpc-url mainnet`.
  function run() external {
    preflight();

    string memory path = "./out/.seatbelt/RotateEarnSentinelsProposal.json";
    vm.createDir("./out/.seatbelt/", true);
    vm.writeFile({
      path: path,
      data: GovernanceSeatbelt.toJson({
        proposal: buildProposal(uniswap), governorBravo: uniswap.ethereum.governorBravo
      })
    });
    console.log("wrote", path);
  }

  /// @dev `preflight()` at a block the caller names, for the fork test and for checking mainnet
  ///      before proposing. Pin the fork to the same block so the two cannot disagree:
  ///      `--sig "preflight(uint256)" $B --rpc-url mainnet --fork-block-number $B`.
  function preflight(uint256 blockNumber) public view {
    require(block.number == blockNumber, "block number");
    preflight();
  }

  /// @dev Every vault is owned by the Timelock, has its legacy sentinel set, and does not have its
  ///      new sentinel set. Logs the block it ran at.
  function preflight() public view {
    smokeCheck();

    require(block.chainid == ChainId.Ethereum, "not Ethereum");
    console.log("preflight at block", block.number);

    address timelock = uniswap.ethereum.timelock;

    // UNI-USDC
    require(IVaultV2(Earn.UNI_USDC).owner() == timelock, "uniUSDC.owner");
    require(IVaultV2(Earn.UNI_USDC).isSentinel(Sentinels.UNI_USDC_LEGACY), "uniUSDC.legacySentinel");
    require(!IVaultV2(Earn.UNI_USDC).isSentinel(Sentinels.UNI_USDC_NEW), "uniUSDC.newSentinel");
    console.log("uniUSDC ready", Earn.UNI_USDC);

    // UNI-USDT
    require(IVaultV2(Earn.UNI_USDT).owner() == timelock, "uniUSDT.owner");
    require(IVaultV2(Earn.UNI_USDT).isSentinel(Sentinels.UNI_USDT_LEGACY), "uniUSDT.legacySentinel");
    require(!IVaultV2(Earn.UNI_USDT).isSentinel(Sentinels.UNI_USDT_NEW), "uniUSDT.newSentinel");
    console.log("uniUSDT ready", Earn.UNI_USDT);

    // UNI-ETH
    require(IVaultV2(Earn.UNI_ETH).owner() == timelock, "uniETH.owner");
    require(IVaultV2(Earn.UNI_ETH).isSentinel(Sentinels.UNI_ETH_LEGACY), "uniETH.legacySentinel");
    require(!IVaultV2(Earn.UNI_ETH).isSentinel(Sentinels.UNI_ETH_NEW), "uniETH.newSentinel");
    console.log("uniETH ready", Earn.UNI_ETH);
  }

  /// @dev Every vault has its new sentinel set and its legacy sentinel unset. The fork test calls
  ///      this after executing the proposal; after the proposal executes onchain, run it against
  ///      Ethereum to verify the outcome: `--sig "postflight()" --rpc-url mainnet`.
  function postflight() public view {
    require(block.chainid == ChainId.Ethereum, "not Ethereum");
    console.log("postflight at block", block.number);

    // UNI-USDC
    require(IVaultV2(Earn.UNI_USDC).isSentinel(Sentinels.UNI_USDC_NEW), "uniUSDC.newSentinel");
    require(
      !IVaultV2(Earn.UNI_USDC).isSentinel(Sentinels.UNI_USDC_LEGACY), "uniUSDC.legacySentinel"
    );
    console.log("uniUSDC sentinel rotated", Earn.UNI_USDC);

    // UNI-USDT
    require(IVaultV2(Earn.UNI_USDT).isSentinel(Sentinels.UNI_USDT_NEW), "uniUSDT.newSentinel");
    require(
      !IVaultV2(Earn.UNI_USDT).isSentinel(Sentinels.UNI_USDT_LEGACY), "uniUSDT.legacySentinel"
    );
    console.log("uniUSDT sentinel rotated", Earn.UNI_USDT);

    // UNI-ETH
    require(IVaultV2(Earn.UNI_ETH).isSentinel(Sentinels.UNI_ETH_NEW), "uniETH.newSentinel");
    require(!IVaultV2(Earn.UNI_ETH).isSentinel(Sentinels.UNI_ETH_LEGACY), "uniETH.legacySentinel");
    console.log("uniETH sentinel rotated", Earn.UNI_ETH);
  }
}
