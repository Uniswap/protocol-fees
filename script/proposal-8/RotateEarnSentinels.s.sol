// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";

import {Uniswap} from "govkit/types/Uniswap.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {Proposal} from "govkit/types/Proposal.sol";
import {Call, LibCall} from "govkit/types/Call.sol";
import {GovernanceSeatbelt} from "govkit/forge/GovernanceSeatbelt.sol";

import {Earn, LibEarn, Sentinels} from "./Constants.sol";
import {IVaultV2} from "./Interfaces.sol";
import {DESCRIPTION} from "./Description.sol";

contract RotateEarnSentinels is Script {
  Uniswap internal uniswap;
  Earn internal earn;

  constructor() {
    uniswap.loadLatest();
    earn = LibEarn.loadLatest();
  }

  // Adding a sentinel is a `true` flag, removing a sentinel is a `false` flag.
  bool internal constant REMOVE = false;
  bool internal constant ADD = true;

  /// @dev Asserts the state the proposal depends on, then writes it for Governance Seatbelt.
  ///      Run against Ethereum: `forge script ... --rpc-url mainnet`.
  function run() external {
    require(keccak256(bytes(DESCRIPTION)) != keccak256(bytes("TODO")), "DESCRIPTION not set");

    preflight();

    string memory path = "./out/.seatbelt/RotateEarnSentinelsProposal.json";
    vm.createDir("./out/.seatbelt/", true);
    vm.writeFile({
      path: path,
      data: GovernanceSeatbelt.toJson({
        proposal: proposal(), governorBravo: uniswap.ethereum.governorBravo
      })
    });
    console.log("wrote", path);
  }

  /// @dev Every vault is owned by the Timelock, has its legacy sentinel set, and does not have its
  ///      new sentinel set. Also a standalone entrypoint: `--sig "preflight()"`.
  function preflight() public view {
    require(block.chainid == ChainId.Ethereum, "not Ethereum");
    console.log("preflight at block", block.number);

    address timelock = uniswap.ethereum.timelock;

    // UNI-USDC
    require(IVaultV2(earn.uniUSDC).owner() == timelock, "uniUSDC.owner");
    require(IVaultV2(earn.uniUSDC).isSentinel(Sentinels.UNI_USDC_LEGACY), "uniUSDC.legacySentinel");
    require(!IVaultV2(earn.uniUSDC).isSentinel(Sentinels.UNI_USDC_NEW), "uniUSDC.newSentinel");
    console.log("uniUSDC ready", earn.uniUSDC);

    // UNI-USDT
    require(IVaultV2(earn.uniUSDT).owner() == timelock, "uniUSDT.owner");
    require(IVaultV2(earn.uniUSDT).isSentinel(Sentinels.UNI_USDT_LEGACY), "uniUSDT.legacySentinel");
    require(!IVaultV2(earn.uniUSDT).isSentinel(Sentinels.UNI_USDT_NEW), "uniUSDT.newSentinel");
    console.log("uniUSDT ready", earn.uniUSDT);

    // UNI-ETH
    require(IVaultV2(earn.uniETH).owner() == timelock, "uniETH.owner");
    require(IVaultV2(earn.uniETH).isSentinel(Sentinels.UNI_ETH_LEGACY), "uniETH.legacySentinel");
    require(!IVaultV2(earn.uniETH).isSentinel(Sentinels.UNI_ETH_NEW), "uniETH.newSentinel");
    console.log("uniETH ready", earn.uniETH);
  }

  /// @dev Every vault has its new sentinel set and its legacy sentinel unset. The fork test calls
  ///      this after executing the proposal; after the proposal executes onchain, run it against
  ///      Ethereum to verify the outcome: `--sig "postflight()"`.
  function postflight() public view {
    require(block.chainid == ChainId.Ethereum, "not Ethereum");
    console.log("postflight at block", block.number);

    // UNI-USDC
    require(IVaultV2(earn.uniUSDC).isSentinel(Sentinels.UNI_USDC_NEW), "uniUSDC.newSentinel");
    require(!IVaultV2(earn.uniUSDC).isSentinel(Sentinels.UNI_USDC_LEGACY), "uniUSDC.legacySentinel");
    console.log("uniUSDC sentinel rotated", earn.uniUSDC);

    // UNI-USDT
    require(IVaultV2(earn.uniUSDT).isSentinel(Sentinels.UNI_USDT_NEW), "uniUSDT.newSentinel");
    require(!IVaultV2(earn.uniUSDT).isSentinel(Sentinels.UNI_USDT_LEGACY), "uniUSDT.legacySentinel");
    console.log("uniUSDT sentinel rotated", earn.uniUSDT);

    // UNI-ETH
    require(IVaultV2(earn.uniETH).isSentinel(Sentinels.UNI_ETH_NEW), "uniETH.newSentinel");
    require(!IVaultV2(earn.uniETH).isSentinel(Sentinels.UNI_ETH_LEGACY), "uniETH.legacySentinel");
    console.log("uniETH sentinel rotated", earn.uniETH);
  }

  /// @dev The proposal, built here so the fork test executes the same calls the script writes.
  function proposal() public view returns (Proposal memory) {
    // ---------------------------------------------------------------------------------------------
    // 00: Add new sentinel to uniUSDC
    //
    Call memory addUniUSDCSentinel = Call({
      target: earn.uniUSDC,
      value: 0,
      data: abi.encodeCall(IVaultV2.setIsSentinel, (Sentinels.UNI_USDC_NEW, ADD))
    });

    // ---------------------------------------------------------------------------------------------
    // 01: Remove legacy sentinel from uniUSDC
    //
    Call memory removeUniUSDCSentinel = Call({
      target: earn.uniUSDC,
      value: 0,
      data: abi.encodeCall(IVaultV2.setIsSentinel, (Sentinels.UNI_USDC_LEGACY, REMOVE))
    });

    // ---------------------------------------------------------------------------------------------
    // 02: Add new sentinel to uniUSDT
    //
    Call memory addUniUSDTSentinel = Call({
      target: earn.uniUSDT,
      value: 0,
      data: abi.encodeCall(IVaultV2.setIsSentinel, (Sentinels.UNI_USDT_NEW, ADD))
    });

    // ---------------------------------------------------------------------------------------------
    // 03: Remove legacy sentinel from uniUSDT
    //
    Call memory removeUniUSDTSentinel = Call({
      target: earn.uniUSDT,
      value: 0,
      data: abi.encodeCall(IVaultV2.setIsSentinel, (Sentinels.UNI_USDT_LEGACY, REMOVE))
    });

    // ---------------------------------------------------------------------------------------------
    // 04: Add new sentinel to uniETH
    //
    Call memory addUniETHSentinel = Call({
      target: earn.uniETH,
      value: 0,
      data: abi.encodeCall(IVaultV2.setIsSentinel, (Sentinels.UNI_ETH_NEW, ADD))
    });

    // ---------------------------------------------------------------------------------------------
    // 05: Remove legacy sentinel from uniETH
    //
    Call memory removeUniETHSentinel = Call({
      target: earn.uniETH,
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
}
