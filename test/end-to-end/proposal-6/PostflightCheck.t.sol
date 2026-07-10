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

import {IArbitrumOrbitResourceFirepit} from "../../../script/proposal-6/Interfaces.sol";
import "../../../script/proposal-6/Constants.sol" as Constants;

contract PostflightCheckTest is Test {
  Uniswap internal uniswap;
  Recorder internal recorder;

  function setUp() external {
    bool shouldRun = vm.envOr("PROP6_POSTFLIGHT", false);
    vm.skip(!shouldRun);
  }

  function testProtocolState() external {
    address aliasedTimelock = InboxEncoder.arbitrumAlias(uniswap.ethereum.timelock);
    address tokenJar =
      recorder.read({chainId: Constants.Robinhood.CHAIN_ID, deploymentName: "TokenJar"});
    address releaser =
      recorder.read({chainId: Constants.Robinhood.CHAIN_ID, deploymentName: "Releaser"});
    address v3OpenFeeAdapter =
      recorder.read({chainId: Constants.Robinhood.CHAIN_ID, deploymentName: "V3OpenFeeAdapter"});

    vm.createSelectFork("fork_robinhood");

    assertEq(IUniswapV2Factory(Constants.Robinhood.V2_FACTORY).feeTo(), tokenJar);
    assertEq(IUniswapV2Factory(Constants.Robinhood.V2_FACTORY).feeToSetter(), aliasedTimelock);
    assertEq(IUniswapV3Factory(Constants.Robinhood.V3_FACTORY).owner(), v3OpenFeeAdapter);
    assertEq(IV3OpenFeeAdapter(v3OpenFeeAdapter).owner(), aliasedTimelock);
    assertEq(IV3OpenFeeAdapter(v3OpenFeeAdapter).feeSetter(), aliasedTimelock);
    assertEq(IV3OpenFeeAdapter(v3OpenFeeAdapter).FACTORY(), Constants.Robinhood.V3_FACTORY);
    assertEq(IV3OpenFeeAdapter(v3OpenFeeAdapter).TOKEN_JAR(), tokenJar);
    assertEq(
      IArbitrumOrbitResourceFirepit(releaser).L2_GATEWAY_ROUTER(),
      Constants.Robinhood.L2_GATEWAY_ROUTER
    );
    assertEq(IReleaser(releaser).RESOURCE(), Constants.Robinhood.UNI);
    assertEq(IReleaser(releaser).TOKEN_JAR(), tokenJar);
    assertEq(IReleaser(releaser).RESOURCE_RECIPIENT(), releaser);
  }
}
