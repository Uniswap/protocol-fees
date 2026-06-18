// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";

import {Uniswap} from "govkit/types/Uniswap.sol";
import {Proposal} from "govkit/types/Proposal.sol";
import {Call, LibCall} from "govkit/types/Call.sol";
import {GovernanceSeatbelt} from "govkit/forge/GovernanceSeatbelt.sol";
import {IUniswapV2Factory} from "govkit/interfaces/IUniswapV2Factory.sol";
import {IUniswapV3Factory} from "govkit/interfaces/IUniswapV3Factory.sol";
import {IPoolManager} from "govkit/interfaces/IPoolManager.sol";
import {IV3OpenFeeAdapter} from "govkit/interfaces/IV3OpenFeeAdapter.sol";

import "../../../script/proposal-5/Constants.sol" as Constants;
import {IOmnichainProposalSender} from "../../../script/proposal-5/Interfaces.sol";
import {LayerZeroEncoder} from "../../../script/proposal-5/LayerZeroEncoder.sol";

contract Proposal5PostflightCheckTest is Test {
  Uniswap internal uniswap;

  function setUp() public {
    bool shouldRun = vm.envOr("PROP5_POSTFLIGHT", false);
    vm.skip(!shouldRun);

    uniswap.loadLatest();
  }

  function testPostflight() external {
    {
      vm.createSelectFork("avalanche");

      // -------------------------------------------------------------------------------------------
      // Check V2 Factory Owner
      //
      address v2FactoryFeeToSetter = IUniswapV2Factory(uniswap.avalanche.v2Factory).feeToSetter();

      assertEq(v2FactoryFeeToSetter, Constants.Avalanche.WORMHOLE_RECEIVER);

      // -------------------------------------------------------------------------------------------
      // Check V3 Factory Owner
      //
      address v3FactoryOwner = IUniswapV3Factory(uniswap.avalanche.v3Factory).owner();

      assertEq(v3FactoryOwner, Constants.Avalanche.WORMHOLE_RECEIVER);

      // -------------------------------------------------------------------------------------------
      // Check Pool Manager Owner
      //
      address poolManagerOwner = IPoolManager(uniswap.avalanche.poolManager).owner();

      assertEq(poolManagerOwner, Constants.Avalanche.WORMHOLE_RECEIVER);
    }

    {
      vm.createSelectFork("mega_eth");

      // -------------------------------------------------------------------------------------------
      // Check V2 Factory Owner
      //
      address v2FactoryFeeToSetter = IUniswapV2Factory(uniswap.megaEth.v2Factory).feeToSetter();

      assertEq(v2FactoryFeeToSetter, Constants.MegaEth.WORMHOLE_RECEIVER);

      // -------------------------------------------------------------------------------------------
      // Check V3 Factory Owner
      //
      address v3FactoryOwner = IUniswapV3Factory(uniswap.megaEth.v3Factory).owner();

      assertEq(v3FactoryOwner, Constants.MegaEth.WORMHOLE_RECEIVER);

      // -------------------------------------------------------------------------------------------
      // Check Pool Manager Owner
      //
      address poolManagerOwner = IPoolManager(uniswap.megaEth.poolManager).owner();

      assertEq(poolManagerOwner, Constants.MegaEth.WORMHOLE_RECEIVER);
    }

    {
      vm.createSelectFork("soneium");

      // -------------------------------------------------------------------------------------------
      // Check V2 Factory Owner
      //
      address v2FactoryFeeToSetter = IUniswapV2Factory(uniswap.soneium.v2Factory).feeToSetter();

      assertEq(v2FactoryFeeToSetter, Constants.Soneium.CROSS_CHAIN_ACCOUNT);

      // -------------------------------------------------------------------------------------------
      // Check V3 Factory Owner
      //
      address v3FactoryOwner = IUniswapV3Factory(uniswap.soneium.v3Factory).owner();

      assertEq(v3FactoryOwner, uniswap.soneium.v3OpenFeeAdapter);

      // -------------------------------------------------------------------------------------------
      // Check V3 Open Fee Adapter Owner
      //
      address v3OpenFeeAdapterOwner = IV3OpenFeeAdapter(uniswap.soneium.v3OpenFeeAdapter).owner();

      assertEq(v3OpenFeeAdapterOwner, Constants.Soneium.CROSS_CHAIN_ACCOUNT);

      // -------------------------------------------------------------------------------------------
      // Check Pool Manager Owner
      //
      address poolManagerOwner = IPoolManager(uniswap.soneium.poolManager).owner();

      assertEq(poolManagerOwner, Constants.Soneium.CROSS_CHAIN_ACCOUNT);
    }

    {
      vm.createSelectFork("xlayer");

      // -------------------------------------------------------------------------------------------
      // Check V2 Factory Owner
      //
      address v2FactoryFeeToSetter = IUniswapV2Factory(uniswap.xLayer.v2Factory).feeToSetter();

      assertEq(v2FactoryFeeToSetter, Constants.XLayer.CROSS_CHAIN_ACCOUNT);

      // -------------------------------------------------------------------------------------------
      // Check V3 Factory Owner
      //
      address v3FactoryOwner = IUniswapV3Factory(uniswap.xLayer.v3Factory).owner();

      assertEq(v3FactoryOwner, uniswap.xLayer.v3OpenFeeAdapter);

      // -------------------------------------------------------------------------------------------
      // Check V3 Open Fee Adapter Owner
      //
      address v3OpenFeeAdapterOwner = IV3OpenFeeAdapter(uniswap.xLayer.v3OpenFeeAdapter).owner();

      assertEq(v3OpenFeeAdapterOwner, Constants.XLayer.CROSS_CHAIN_ACCOUNT);

      // -------------------------------------------------------------------------------------------
      // Check Pool Manager Owner
      //
      address poolManagerOwner = IPoolManager(uniswap.xLayer.poolManager).owner();

      assertEq(poolManagerOwner, Constants.XLayer.CROSS_CHAIN_ACCOUNT);
    }
  }

  function decodeTrustedRemote(bytes memory encoded) internal pure returns (address, address) {
    if (encoded.length == 0) return (address(0x00), address(0x00));

    if (encoded.length != 40) revert("PreflightCheckTest::decodeTrustedRemote: Invalid Length");

    address sender;
    address receiver;

    assembly {
      sender := mload(add(encoded, 0x20))
      sender := shr(0x60, sender)

      receiver := mload(add(encoded, 0x34))
      receiver := shr(0x60, receiver)
    }

    return (sender, receiver);
  }

  function optimismAlias(address l1Address) internal pure returns (address) {
    unchecked {
      return address(uint160(l1Address) + Constants.OpStack.ALIAS);
    }
  }
}
