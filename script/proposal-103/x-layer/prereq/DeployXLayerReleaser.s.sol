// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {ChainId} from "govkit/constants/ChainId.sol";

import {XLayerReleaser} from "../../../../src/releasers/XLayerReleaser.sol";
import {DecayingThresholdSetter} from "../../../../src/DecayingThresholdSetter.sol";
import {RECORD_NAME, Records, XLayer, smokeCheck} from "../Constants.sol";
import {checkNewReleaser, checkThresholdSetter} from "../ReleaserCheck.sol";

// -------------------------------------------------------------------------------------------------
// NOTICE:
//
// Deploys the releaser the proposal installs on the X Layer TokenJar, and the
// {DecayingThresholdSetter} the proposal starts. Makes the setter the releaser's owner and the
// CrossChainAccount its threshold-setter, then records both addresses in `.records/XLayer.json`,
// where the proposal reads them. Anyone can run it. The deployer holds no authority once it
// finishes.
//
// forge script script/proposal-103/x-layer/prereq/DeployXLayerReleaser.s.sol --rpc-url xlayer \
//   --broadcast
//
// `run` asserts the result in its own simulation before it records anything. To apply the same
// assertions to the live chain afterwards, from the record alone:
//
// forge script script/proposal-103/x-layer/prereq/DeployXLayerReleaser.s.sol --sig "check()" \
//   --rpc-url xlayer
//
contract DeployXLayerReleaser is Script {
  Recorder internal recorder;
  Uniswap internal uniswap;

  XLayerReleaser internal releaser;
  DecayingThresholdSetter internal thresholdSetter;

  function run() external {
    _initialize();

    // The recorder writes only after the checks pass, and never in a dry run, so a record here
    // means an earlier `--broadcast` run simulated cleanly. Overwriting it would make the record
    // disagree with a proposal built from it. To redeploy, clear the record first.
    require(
      !recorder.exists({chainId: ChainId.XLayer, deploymentName: Records.RELEASER})
        && !recorder.exists({chainId: ChainId.XLayer, deploymentName: Records.THRESHOLD_SETTER}),
      "already deployed: clear .records/ to redeploy"
    );

    address crossChainAccount = uniswap.xLayer.crossChainAccount;

    vm.startBroadcast();

    // -----------------------------------------------------------------------------------------
    // Transaction 00
    //
    // Deploy {XLayerReleaser}. The deployer owns it until transaction 03.
    //
    // Parameters:
    //
    // - `_bridge`: the unified bridge on X Layer.
    // - `_resource`: the bridge's wrapped UNI.
    // - `_l1Resource`: UNI on Ethereum, which the bridge maps `_resource` to.
    // - `_threshold`: the setter's start threshold, which {DecayingThresholdSetter-start} requires
    //   the releaser to meet.
    // - `_tokenJar`: the X Layer TokenJar.
    //
    releaser = new XLayerReleaser({
      _bridge: XLayer.TOKEN_BRIDGE,
      _resource: XLayer.RESOURCE,
      _l1Resource: uniswap.ethereum.uni,
      _threshold: XLayer.START_THRESHOLD,
      _tokenJar: uniswap.xLayer.tokenJar
    });

    // -----------------------------------------------------------------------------------------
    // Transaction 01
    //
    // Deploy {DecayingThresholdSetter} for the releaser. Its constructor reads its governance from
    // the TokenJar's owner, the CrossChainAccount.
    //
    // Parameters:
    //
    // - `_releaser`: the releaser from transaction 00.
    // - `_startThreshold`: the threshold when the decay starts.
    // - `_floorThreshold`: the threshold the decay ends at.
    // - `_halfLife`: the time over which the threshold halves.
    //
    thresholdSetter = new DecayingThresholdSetter({
      _releaser: address(releaser),
      _startThreshold: XLayer.START_THRESHOLD,
      _floorThreshold: XLayer.FLOOR_THRESHOLD,
      _halfLife: XLayer.HALF_LIFE
    });

    // -----------------------------------------------------------------------------------------
    // Transaction 02
    //
    // Make the CrossChainAccount the releaser's threshold-setter. The proposal's
    // {DecayingThresholdSetter-start} makes the setter the threshold-setter in its place.
    releaser.setThresholdSetter({_thresholdSetter: crossChainAccount});

    // -----------------------------------------------------------------------------------------
    // Transaction 03
    //
    // Transfer ownership of the releaser to the {DecayingThresholdSetter}, which
    // {DecayingThresholdSetter-start} requires. The setter returns ownership to the
    // CrossChainAccount once the threshold reaches the floor.
    releaser.transferOwnership({newOwner: address(thresholdSetter)});

    vm.stopBroadcast();

    checkNewReleaser(uniswap, address(releaser), address(thresholdSetter));
    checkThresholdSetter(uniswap, address(thresholdSetter), address(releaser));
    recorder.write({
      chainId: ChainId.XLayer, deploymentName: Records.RELEASER, deployment: address(releaser)
    });
    recorder.write({
      chainId: ChainId.XLayer,
      deploymentName: Records.THRESHOLD_SETTER,
      deployment: address(thresholdSetter)
    });
    console.log("XLayerReleaser:", address(releaser));
    console.log("DecayingThresholdSetter:", address(thresholdSetter));
  }

  /// @dev Verifies a recorded deployment against the chain the script points at. {run} applies the
  ///      same assertions to its own simulation before it records. {check} applies them to live
  ///      state, reading the deployment from the record. It passes only before the proposal
  ///      executes, because {DecayingThresholdSetter-start} sets the setter's `startTime`.
  function check() external {
    _initialize();
    address recordedReleaser =
      recorder.read({chainId: ChainId.XLayer, deploymentName: Records.RELEASER});
    address recordedThresholdSetter =
      recorder.read({chainId: ChainId.XLayer, deploymentName: Records.THRESHOLD_SETTER});
    checkNewReleaser(uniswap, recordedReleaser, recordedThresholdSetter);
    checkThresholdSetter(uniswap, recordedThresholdSetter, recordedReleaser);
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
