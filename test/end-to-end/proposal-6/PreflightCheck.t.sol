// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {InboxEncoder} from "govkit/bridges/InboxEncoder.sol";
import {GovernanceSeatbelt} from "lib/govkit/src/forge/GovernanceSeatbelt.sol";
import {Call, LibCall} from "lib/govkit/src/types/Call.sol";
import {Proposal} from "lib/govkit/src/types/Proposal.sol";

import {IUniswapV2Factory} from "govkit/interfaces/IUniswapV2Factory.sol";
import {IUniswapV3Factory} from "govkit/interfaces/IUniswapV3Factory.sol";
import {IPoolManager} from "govkit/interfaces/IPoolManager.sol";
import {ITokenJar} from "govkit/interfaces/ITokenJar.sol";
import {IReleaser} from "govkit/interfaces/IReleaser.sol";
import {IV3OpenFeeAdapter} from "govkit/interfaces/IV3OpenFeeAdapter.sol";

import "../../../script/proposal-6/Constants.sol" as Constants;

contract PreflightCheckTest is Test {
  Uniswap internal uniswap;
  Recorder internal recorder;

  function setUp() external {
    bool shouldRun = vm.envOr("PROP6_PREFLIGHT", false);
    vm.skip(!shouldRun);
  }

  function testProtocolState() external {
    address aliasedTimelock = InboxEncoder.arbitrumAlias(uniswap.ethereum.timelock);

    vm.createSelectFork("fork_robinhood");

    assertEq(IUniswapV2Factory(Constants.Robinhood.V2_FACTORY).feeTo(), address(0x00));
    assertEq(IUniswapV2Factory(Constants.Robinhood.V2_FACTORY).feeToSetter(), aliasedTimelock);
    assertEq(IUniswapV3Factory(Constants.Robinhood.V3_FACTORY).owner(), aliasedTimelock);
  }
}
