// SPDX-License-Identifier: AGPl-3.0-only
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Recorder} from "govkit/forge/Recorder.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {InboxEncoder} from "govkit/bridges/InboxEncoder.sol";

import {ITokenJar} from "govkit/interfaces/ITokenJar.sol";
import {IReleaser} from "govkit/interfaces/IReleaser.sol";
import {IV3OpenFeeAdapter} from "govkit/interfaces/IV3OpenFeeAdapter.sol";

import {ArbitrumOrbitDeployer} from "../../deployers/ArbitrumOrbitDeployer.sol";
import {IL1ERC20Gateway} from "../Interfaces.sol";
import "../Constants.sol" as Constants;

string constant DEPLOYER_NAME = "ArbitrumOrbitDeployer";
uint256 constant THRESHOLD = 2000e18;

contract DeployFeeInfraRobinhood is Script {
  Recorder internal recorder;
  Uniswap internal uniswap;
  ArbitrumOrbitDeployer internal deployer;

  function run() external {
    uniswap.loadLatest();
    recorder.initialize({scriptName: "DeployFeeInfraRobinhood"});

    address timelockAlias = InboxEncoder.arbitrumAlias(uniswap.ethereum.timelock);

    // -----------------------------------------------------------------------------------------
    // Deploy ArbitrumOrbitDeployer
    //
    // Deploys the fee infra, configures it, and transfers it to the aliased timelock.
    //
    if (!recorder.exists(Constants.Robinhood.CHAIN_ID, DEPLOYER_NAME)) {
      vm.startBroadcast();

      deployer = new ArbitrumOrbitDeployer({
        _l2GatewayRouter: Constants.Robinhood.L2_GATEWAY_ROUTER,
        _resource: Constants.Robinhood.UNI,
        _l1Resource: uniswap.ethereum.uni,
        _threshold: THRESHOLD,
        _owner: timelockAlias,
        _v3Factory: Constants.Robinhood.V3_FACTORY
      });

      vm.stopBroadcast();

      recorder.write({
        chainId: Constants.Robinhood.CHAIN_ID,
        deploymentName: DEPLOYER_NAME,
        deployment: address(deployer)
      });
    } else {
      deployer = ArbitrumOrbitDeployer(
        recorder.read({chainId: Constants.Robinhood.CHAIN_ID, deploymentName: DEPLOYER_NAME})
      );
    }

    require(address(deployer) != address(0x00), "deployer is null");

    address tokenJar = address(deployer.TOKEN_JAR());
    address releaser = address(deployer.RELEASER());
    address v3OpenFeeAdapter = address(deployer.V3_OPEN_FEE_ADAPTER());

    // -----------------------------------------------------------------------------------------
    // Run checks
    //

    require(ITokenJar(tokenJar).owner() == timelockAlias);
    require(IReleaser(releaser).thresholdSetter() == timelockAlias);
    require(IReleaser(releaser).owner() == timelockAlias);
    require(IV3OpenFeeAdapter(v3OpenFeeAdapter).owner() == timelockAlias);
    require(IV3OpenFeeAdapter(v3OpenFeeAdapter).feeSetter() == timelockAlias);

    // -----------------------------------------------------------------------------------------
    // Write deployments to disk
    //
    recorder.write({
      chainId: Constants.Robinhood.CHAIN_ID,
      deploymentName: DEPLOYER_NAME,
      deployment: address(deployer)
    });
    recorder.write({
      chainId: Constants.Robinhood.CHAIN_ID, deploymentName: "TokenJar", deployment: tokenJar
    });
    recorder.write({
      chainId: Constants.Robinhood.CHAIN_ID, deploymentName: "Releaser", deployment: releaser
    });
    recorder.write({
      chainId: Constants.Robinhood.CHAIN_ID,
      deploymentName: "V3OpenFeeAdapter",
      deployment: v3OpenFeeAdapter
    });
  }
}
