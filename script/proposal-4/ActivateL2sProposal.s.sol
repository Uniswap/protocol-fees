// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";

import "./Constants.sol" as Constants;
import {
  IWormholeSender,
  IUniswapV2Factory,
  IUniswapV3Factory,
  IUniswapV4PoolManager,
  IGovernorBravo,
  IPolygonFXRoot,
  ILayerZeroEndpoint
} from "./Interfaces.sol";
import {ProposalAction, toItems} from "./Types.sol";
using {toItems} for ProposalAction[];

string constant PROPOSAL_DESCRIPTION = "TODO";

/// @title Activate L2's (Plus Celo Retry)
contract ActivateL2Proposals is Script {
  /// @notice Runs the actions
  function run() public {
    // check addresses are non-zero.
    Constants.smokeCheck();

    // construct actions & decompose to governor parameters.
    (
      address[] memory targets,
      uint256[] memory values,
      string[] memory signatures,
      bytes[] memory datas
    ) = _getActions().toItems();

    // initiate the broadcast.
    vm.startBroadcast();

    // propose.
    IGovernorBravo(Constants.L1.TIMELOCK)
      .propose(targets, values, signatures, datas, PROPOSAL_DESCRIPTION);

    // stop the broadcast.
    vm.stopBroadcast();
  }

  function _getActions() internal pure returns (ProposalAction[] memory actions) {
    actions = new ProposalAction[](5);

    // ---------------------------------------------------------------------------------------------
    // STEP 1:
    //
    // Celo: Sets fee collector of `UniswapV2Factory` to `TokenJar`, transfers ownership of
    // `UniswapV2Factory` and `PoolManager` to Optimism `CrossChainAccount`, transfers ownerhsip of
    // `UniswapV3Factory` to `V3OpenFeeAdapter`.
    //
    // DOES NOT activate V4 fees, only V2 and V3.
    //
    // Context:
    // ---
    //
    // The original flow was:
    //
    // Proposal 2 would:
    //
    // - From `UniswapWormholeMesageReceiver`:
    //   - On `UniswapV3Factory` set owner to `CrossChainAccout`.
    //   - On `UniswapV2Factory` set fee collector setter to `CrossChainAccout`.
    //   - On `PoolManager` set owner to `CrossChainAccout`.
    //
    // Proposal 3 would:
    //
    // - From `CrossChainAccout`:
    //   - On `UniswapV3Factory` set owner to `V3OpenFeeAdapter`.
    //   - On `UniswapV2Factory` set fee collector to `TokenJar`.
    //
    // However, these failed.
    //
    // The following were deployed and configured permissionlessly:
    //
    // - `TokenJar`
    // - `OptimismBridgedResourceFirepit`
    // - `V3OpenFeeAdapter`
    //
    // So the state of the system before this proposal is:
    //
    // - `UniswapV2Factory.feeTo` is `address(0x00)`.
    // - `UniswapV2Factory.feeToSetter` is `UniswapWormholeMesageReceiver`.
    // - `UniswapV3Factory.owner` is `UniswapWormholeMesageReceiver`.
    // - `PoolManager.owner` is `UniswapWormholeMesageReceiver`.
    // - `TokenJar.owner` is `CrossChainAccout`.
    // - `V3OpenFeeAdapter.owner` is `CrossChainAccout`.
    //
    // Actions:
    // ---
    //
    // - From `UniswapWormholeMesageReceiver`:
    //   - Set`UniswapV2Factory.feeTo` to `TokenJar`.
    //   - Set`UniswapV2Factory.feeToSetter` to `CrossChainAccout`.
    //   - Set`UniswapV3Factory.owner` to `V3OpenFeeAdapter`.
    //   - Set`PoolManager.owner` to `CrossChainAccout`.
    //
    {
      address[] memory targets = new address[](4);
      uint256[] memory values = new uint256[](4);
      bytes[] memory datas = new bytes[](4);

      targets[0] = Constants.Celo.V2_FACTORY;
      values[0] = 0;
      datas[0] = abi.encodeCall(IUniswapV2Factory.setFeeTo, (Constants.Celo.TOKEN_JAR));

      targets[1] = Constants.Celo.V2_FACTORY;
      values[1] = 0;
      datas[1] = abi.encodeCall(IUniswapV2Factory.setFeeToSetter, (Constants.Celo.CROSS_CHAIN_ACCOUNT));

      targets[2] = Constants.Celo.V3_FACTORY;
      values[2] = 0;
      datas[2] = abi.encodeCall(IUniswapV3Factory.setOwner, (Constants.Celo.V3_OPEN_FEE_ADAPTER));

      targets[3] = Constants.Celo.V4_POOL_MANAGER;
      values[3] = 0;
      datas[3] = abi.encodeCall(IUniswapV4PoolManager.transferOwnership, (Constants.Celo.CROSS_CHAIN_ACCOUNT));

      actions[0] = ProposalAction({
        target: Constants.L1.WORMHOLE_SENDER,
        value: 0,
        signature: "",
        data: abi.encodeCall(
          IWormholeSender.sendMessage,
          (
            targets,
            values,
            datas,
            Constants.Celo.UNISWAP_WORMHOLE_MESSAGE_RECEIVER,
            Constants.Wormhole.CELO_CHAIN_ID
          )
        )
      });
    }

    // ---------------------------------------------------------------------------------------------
    // STEP 2:
    //
    // BNB Chain: Sets the fee collector of `UniswapV2Factory` to `TokenJar`, transfers ownership of
    // `UniswapV3Factory` to `V3OpenFeeAdapter`.
    //
    // DOES NOT activate V4 fees, only V2 and V3.
    //
    // Context:
    // ---
    //
    // The `UniswapWormholeMessageReceiver` owns `UniswapV2Factory`, `UniswapV3Factory`, and
    // `PoolManager`. Since we continue to use Wormhole for now, we only set the `UniswapV2Factory`
    // fee collector and transfer ownership of `UniswapV3Factory` to the `V3OpenFeeAdapter` because
    // V3 sends fees to the factory owner.
    //
    // Actions:
    // ---
    //
    // - From `UniswapWormholeMesageReceiver`:
    //   - Set `UniswapV2Factory.feeTo` to `TokenJar`.
    //   - Set `UniswapV3Factory.owner` to `V3OpenFeeAdapter`.
    {
      address[] memory targets = new address[](2);
      uint256[] memory values = new uint256[](2);
      bytes[] memory datas = new bytes[](2);

      targets[0] = Constants.BNB.V2_FACTORY;
      values[0] = 0;
      datas[0] = abi.encodeCall(IUniswapV2Factory.setFeeTo, (Constants.BNB.TOKEN_JAR));

      targets[1] = Constants.BNB.V3_FACTORY;
      values[1] = 0;
      datas[1] = abi.encodeCall(IUniswapV3Factory.setOwner, (Constants.BNB.V3_OPEN_FEE_ADAPTER));

      actions[1] = ProposalAction({
        target: Constants.L1.WORMHOLE_SENDER,
        value: 0,
        signature: "",
        data: abi.encodeCall(
          IWormholeSender.sendMessage,
          (
            targets,
            values,
            datas,
            Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER,
            Constants.Wormhole.BNB_CHAIN_ID
          )
        )
      });
    }

    // ---------------------------------------------------------------------------------------------
    // STEP 3:
    //
    // Polygon Uniswap V2 TODO
    //
    // owner is: 0x8a1B966aC46F42275860f905dbC75EfBfDC12374
    // looks to be some kind of native polygon receiver
    // building calldata according to these independent docs:
    // https://github.com/ScopeLift/uniswap-docs-fork/blob/l2-proposals/docs/concepts/governance/05-multichain-proposals.md#polygon
    //
    // only one action can be taken over the polygon bridge at a time, so we'll need 3 actions.
    actions[2] = ProposalAction({
      target: Constants.L1.POLYGON_FX_ROOT,
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IPolygonFXRoot.sendMessageToChild,
        (
          Constants.Polygon.V2_FACTORY,
          abi.encodeCall(IUniswapV2Factory.setFeeToSetter, (Constants.Polygon.TOKEN_JAR))
        )
      )
    });

    // ---------------------------------------------------------------------------------------------
    // STEP 4:
    //
    // Polygon Uniswap V3 TODO
    actions[3] = ProposalAction({
      target: Constants.L1.POLYGON_FX_ROOT,
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IPolygonFXRoot.sendMessageToChild,
        (
          Constants.Polygon.V3_FACTORY,
          abi.encodeCall(IUniswapV3Factory.setOwner, (Constants.Polygon.TOKEN_JAR))
        )
      )
    });

    // ---------------------------------------------------------------------------------------------
    // STEP 5:
    //
    // Polygon Uniswap V3 TODO
    actions[4] = ProposalAction({
      target: Constants.L1.POLYGON_FX_ROOT,
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IPolygonFXRoot.sendMessageToChild,
        (
          Constants.Polygon.V4_POOL_MANAGER,
          abi.encodeCall(IUniswapV4PoolManager.transferOwnership, (Constants.Polygon.TOKEN_JAR))
        )
      )
    });

    // ---------------------------------------------------------------------------------------------
    // STEP 6:
    //
    // Avalanche V2 (TODO: scrap this, documentation)
    //
    // owned by layer zero omnichain governance contract deployment.
    //
    // layer zero has no v1 documentation, no code comments, no natspec, layer zero llm cannot help,
    // 
    // there's a long line of contracts and issues to track for this. for now we are leaving this
    // unused and undocumented.  we'll add documentation when it is time to migrate off of this
    // mechanism toward a more modular system.
    //
    // links that will be helpful in the future:
    //
    // - l1 lz endpoint v2 (compat w v1): https://etherscan.io/address/0x1a44076050125825900e736c501f859c50fE728c#code
    // - avax lz omnichain gov: https://avascan.info/blockchain/all/address/0xeb0BCF27D1Fb4b25e708fBB815c421Aeb51eA9fc
    // - lz omnichain gov src: https://github.com/LayerZero-Labs/omnichain-governance-executor
    //
    // actions[5] = ProposalAction({
    //   target: Constants.L1.LAYER_ZERO_ENDPOINT,
    //   value: 0,
    //   signature: "",
    //   data: abi.encodeCall(
    //     ILayerZeroEndpoint.send,
    //     (
    //       Constants.LayerZero.AVALANCHE_CHAIN_ID,
    //       hex"aaaaaaaaaaaa", // no idea what "dest" is or why it's arbitrary bytes
    //       hex"aaaaaaaaaaaa", // no idea whether this takes batch actions or not
    //       payable(address(0xaaaaaaaaaaaa)),
    //       address(0xaaaaaaaaaaaa),
    //       hex"aaaaaaaaaaaa" // no idea what adapter params are.
    //     )
    //   )
    // });
  }
}
