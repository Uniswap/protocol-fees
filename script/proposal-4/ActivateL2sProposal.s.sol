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
  IPolygonFxRoot,
  ILayerZeroEndpoint
} from "./Interfaces.sol";

string constant PROPOSAL_DESCRIPTION = "TODO";

/// @title Activate L2's (Plus Celo Retry)
contract ActivateL2Proposals is Script {

  /// @notice Proposal Action Data Type.
  struct ProposalAction {
    address target;
    uint256 value;
    string signature;
    bytes data;
  }

  /// @notice Runs the actions
  function run() public {
    // check addresses are non-zero.
    //
    Constants.smokeCheck();

    // three actions get taken here.
    //
    uint256 actionCount = 3;

    // construct actions for governance.
    //
    ProposalAction[] memory actions = _getActions(actionCount);

    // split actions into arrays of targets, values, signatures, and datas:
    //
    // (address, uint256, string, bytes)[] --> (address[], uint256[], string[], bytes[])
    //
    address[] memory targets = new address[](actionCount);
    uint256[] memory values = new uint256[](actionCount);
    string[] memory signatures = new string[](actionCount);
    bytes[] memory datas = new bytes[](actionCount);

    for (uint256 i; i < actionCount; i++) {
      targets[i] = actions[i].target;
      values[i] = actions[i].value;
      signatures[i] = actions[i].signature;
      datas[i] = actions[i].data;
    }

    // initiate the broadcast.
    vm.startBroadcast();

    // propose.
    IGovernorBravo(Constants.Ethereum.TIMELOCK)
      .propose(targets, values, signatures, datas, PROPOSAL_DESCRIPTION);

    // stop the broadcast.
    vm.stopBroadcast();
  }

  function _getActions(uint256 actionCount) internal pure returns (ProposalAction[] memory actions) {
    actions = new ProposalAction[](actionCount);

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
        target: Constants.Ethereum.WORMHOLE_SENDER,
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
        target: Constants.Ethereum.WORMHOLE_SENDER,
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
    // Polygon: Sets the fee collector of `UniswapV2Factory` to `TokenJar`, transfers ownership of
    // `UniswapV3Factory` to `V3OpenFeeAdapter`.
    //
    // DOES NOT activate V4 fees, only V2 and V3.
    //
    // Context:
    // ---
    //
    // The `EthereumProxy` owns `UniswapV2Factory`, `UniswapV3Factory`, and `PoolManager`. This is
    // the receiver for the Polygon message bridge `FxRoot(Ethereum) -> FxChild(Polygon)`. Since we
    // continue to use Polygon's native bridge for now, we only set the `UniswapV2Factory` fee
    // collector and transfer ownership of `UniswapV3Factory` to the `V3OpenFeeAdapter` because V3
    // sends fees to the factory owner. 
    //
    // Actions:
    // ---
    //
    // - From `EthereumProxy`:
    //   - Set `UniswapV2Factory.feeTo` to `TokenJar`.
    //   - Set `UniswapV3Factory.owner` to `V3OpenFeeAdapter`.
    //
    {
      address[] memory targets = new address[](2);
      uint256[] memory values = new uint256[](2);
      bytes[] memory datas = new bytes[](2);

      targets[0] = Constants.BNB.V2_FACTORY;
      values[0] = 0;
      datas[0] = abi.encodeCall(IUniswapV2Factory.setFeeTo, (Constants.Polygon.TOKEN_JAR));

      targets[1] = Constants.BNB.V3_FACTORY;
      values[1] = 0;
      datas[1] = abi.encodeCall(IUniswapV3Factory.setOwner, (Constants.Polygon.V3_OPEN_FEE_ADAPTER));

      actions[2] = ProposalAction({
        target: Constants.Ethereum.POLYGON_FX_ROOT,
        value: 0,
        signature: "",
        data: abi.encodeCall(
          IPolygonFxRoot.sendMessageToChild,
          (
            Constants.Polygon.FX_MESSAGE_PROCESSOR,
            abi.encode(targets, values, datas)
          )
        )
      });
    }
  }
}
