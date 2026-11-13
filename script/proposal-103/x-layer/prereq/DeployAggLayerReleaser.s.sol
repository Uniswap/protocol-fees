// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {ChainId} from "govkit/constants/ChainId.sol";

import {AggLayerReleaser} from "../../../../src/releasers/AggLayerReleaser.sol";
import {RECORD_NAME, Records, XLayer, smokeCheck} from "../Constants.sol";
import {checkNewReleaser} from "../ReleaserCheck.sol";

// -------------------------------------------------------------------------------------------------
// NOTICE:
//
// Deploys the releaser the proposal installs on the X Layer TokenJar, hands it to the
// CrossChainAccount, and records its address in `.records/XLayer.json`, where the proposal reads
// it. Anyone can run it; the deployer holds no authority once it finishes.
//
// forge script script/proposal-103/x-layer/prereq/DeployAggLayerReleaser.s.sol --rpc-url xlayer \
//   --broadcast
//
// `run` asserts the result in its own simulation before it records anything. To apply the same
// assertions to the live chain afterwards, from the record alone:
//
// forge script script/proposal-103/x-layer/prereq/DeployAggLayerReleaser.s.sol --sig "check()" \
//   --rpc-url xlayer
//
contract DeployAggLayerReleaser is Script {
  Recorder internal recorder;
  Uniswap internal uniswap;

  AggLayerReleaser internal releaser;

  function run() external {
    _initialize();

    // The recorder writes only after `checkNewReleaser` passes and never during a dry run, so a
    // record here means an earlier `--broadcast` run simulated cleanly. Overwriting it would
    // strand the proposal on the old address, so to redeploy, deliberately clear the record.
    require(
      !recorder.exists({chainId: ChainId.XLayer, deploymentName: Records.RELEASER}),
      "already deployed: clear .records/ to redeploy"
    );

    address crossChainAccount = uniswap.xLayer.crossChainAccount;

    vm.startBroadcast();

    // -----------------------------------------------------------------------------------------
    // Transaction 00
    //
    // Deploy `AggLayerReleaser`. The deployer is its owner until transaction 02.
    //
    // Parameters:
    //
    // - `_bridge`: the AggLayer unified bridge on X Layer.
    // - `_resource`: the bridge's wrapped UNI.
    // - `_l1Resource`: UNI on Ethereum, which the bridge maps `_resource` to.
    // - `_threshold`: the initial threshold.
    // - `_tokenJar`: the X Layer TokenJar.
    //
    releaser = new AggLayerReleaser({
      _bridge: XLayer.TOKEN_BRIDGE,
      _resource: XLayer.RESOURCE,
      _l1Resource: uniswap.ethereum.uni,
      _threshold: XLayer.INITIAL_THRESHOLD,
      _tokenJar: uniswap.xLayer.tokenJar
    });

    // -----------------------------------------------------------------------------------------
    // Transaction 01
    //
    // Set the releaser's threshold-setter to the CrossChainAccount.
    //
    // TODO: once the decaying threshold setter is deployed, make it both the threshold-setter here
    // and the owner in transaction 02, and assert both in `checkNewReleaser`. It takes the
    // threshold from 60,000 UNI to 2,000 UNI, then sets the CrossChainAccount as threshold-setter
    // and owner; it needs ownership because only the owner can change the threshold-setter.
    releaser.setThresholdSetter({_thresholdSetter: crossChainAccount});

    // -----------------------------------------------------------------------------------------
    // Transaction 02
    //
    // Transfer ownership of the releaser to the CrossChainAccount.
    releaser.transferOwnership({newOwner: crossChainAccount});

    vm.stopBroadcast();

    checkNewReleaser(uniswap, address(releaser));
    recorder.write({
      chainId: ChainId.XLayer, deploymentName: Records.RELEASER, deployment: address(releaser)
    });
    console.log("AggLayerReleaser:", address(releaser));
  }

  /// @dev Verifies a recorded deployment against the chain the script is pointed at. `run`
  ///      applies the same assertions to its own simulation before recording; this applies them
  ///      to live state, reading the deployment out of the record.
  function check() external {
    _initialize();
    checkNewReleaser(
      uniswap, recorder.read({chainId: ChainId.XLayer, deploymentName: Records.RELEASER})
    );
  }

  /// @dev Preamble shared by `run` and `check`.
  function _initialize() internal {
    smokeCheck();

    uniswap.loadLatest();
    recorder.initialize({scriptName: _recordName()});

    require(block.chainid == ChainId.XLayer, "not X Layer");
  }

  /// @dev The record file for the deployment. Tests override this with a test record name to
  ///      avoid collisions with the real deployment record.
  function _recordName() internal view virtual returns (string memory) {
    return RECORD_NAME;
  }
}
