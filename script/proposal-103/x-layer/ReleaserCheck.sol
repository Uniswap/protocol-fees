// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Uniswap} from "govkit/types/Uniswap.sol";

import {XLayerReleaser} from "../../../src/releasers/XLayerReleaser.sol";
import {DecayingThresholdSetter} from "../../../src/DecayingThresholdSetter.sol";
import {IXLayerBridge} from "../../../src/interfaces/external/IXLayerBridge.sol";
import {XLayer} from "./Constants.sol";

/// @dev Asserts the {XLayerReleaser} at `releaser` has the settings the prerequisite script deploys
///      it with:
///
///      - `XLayer.TOKEN_BRIDGE` as its bridge;
///      - `XLayer.RESOURCE` as its resource, which the bridge maps to UNI on Ethereum;
///      - the X Layer TokenJar as its TokenJar;
///      - `XLayer.START_THRESHOLD` as its threshold;
///      - `thresholdSetter` as its owner;
///      - the CrossChainAccount as its threshold-setter.
///
///      The prerequisite script runs it on its own deployment, and
///      {ReplaceXLayerReleaser-preflightXLayer} on the recorded deployment. It reads the
///      releaser's getters and does not compare its code, so a contract with the same getters
///      passes too.
function checkNewReleaser(Uniswap storage uniswap, address releaser, address thresholdSetter) view {
  require(releaser.code.length != 0, "newReleaser.code");
  XLayerReleaser newReleaser = XLayerReleaser(releaser);

  // Assert the constructor arguments. The releaser checks the bridge's mapping of its resource on
  // every release, but it trusts `BRIDGE` to answer truthfully, so only this check pins the
  // bridge itself.
  require(address(newReleaser.BRIDGE()) == XLayer.TOKEN_BRIDGE, "newReleaser.BRIDGE");
  require(address(newReleaser.RESOURCE()) == XLayer.RESOURCE, "newReleaser.RESOURCE");
  require(newReleaser.L1_RESOURCE() == uniswap.ethereum.uni, "newReleaser.L1_RESOURCE");
  require(address(newReleaser.TOKEN_JAR()) == uniswap.xLayer.tokenJar, "newReleaser.TOKEN_JAR");
  require(newReleaser.RESOURCE_RECIPIENT() == releaser, "newReleaser.RESOURCE_RECIPIENT");
  require(newReleaser.threshold() == XLayer.START_THRESHOLD, "newReleaser.threshold");

  // Assert the owner and the threshold-setter. {DecayingThresholdSetter-start} requires the setter
  // to own the releaser, and makes the setter the threshold-setter in place of the
  // CrossChainAccount.
  require(newReleaser.owner() == thresholdSetter, "newReleaser.owner");
  require(
    newReleaser.thresholdSetter() == uniswap.xLayer.crossChainAccount, "newReleaser.thresholdSetter"
  );

  // Assert the bridge maps the resource to UNI on Ethereum, so releases do not revert with
  // `ResourceNotWrappedL1Resource`.
  (uint32 originNetwork, address originTokenAddress) =
    IXLayerBridge(XLayer.TOKEN_BRIDGE).wrappedTokenToTokenInfo(XLayer.RESOURCE);
  require(
    originNetwork == newReleaser.XLAYER_ETHEREUM_NETWORK_ID(), "bridge.resource.originNetwork"
  );
  require(originTokenAddress == uniswap.ethereum.uni, "bridge.resource.originTokenAddress");
}

/// @dev Asserts the {DecayingThresholdSetter} at `thresholdSetter` has the settings the
///      prerequisite script deploys it with, and has not started:
///
///      - `releaser` as its releaser;
///      - the CrossChainAccount as its governance;
///      - `XLayer.START_THRESHOLD`, `XLayer.FLOOR_THRESHOLD` and `XLayer.HALF_LIFE` as its start
///        threshold, floor threshold and half-life.
///
///      It reads the setter's getters and does not compare its code.
function checkThresholdSetter(Uniswap storage uniswap, address thresholdSetter, address releaser)
  view {
  require(thresholdSetter.code.length != 0, "thresholdSetter.code");
  DecayingThresholdSetter setter = DecayingThresholdSetter(thresholdSetter);

  // Assert the constructor arguments and the governance the constructor read from the TokenJar.
  require(address(setter.RELEASER()) == releaser, "thresholdSetter.RELEASER");
  require(setter.GOVERNANCE() == uniswap.xLayer.crossChainAccount, "thresholdSetter.GOVERNANCE");
  require(setter.START_THRESHOLD() == XLayer.START_THRESHOLD, "thresholdSetter.START_THRESHOLD");
  require(setter.FLOOR_THRESHOLD() == XLayer.FLOOR_THRESHOLD, "thresholdSetter.FLOOR_THRESHOLD");
  require(setter.HALF_LIFE() == XLayer.HALF_LIFE, "thresholdSetter.HALF_LIFE");

  // Assert the decay has not started, or the proposal's {DecayingThresholdSetter-start} reverts
  // with {IDecayingThresholdSetter-AlreadyStarted} or
  // {IDecayingThresholdSetter-ControlAlreadyReturned}.
  require(setter.startTime() == 0, "thresholdSetter.startTime");
  require(!setter.controlReturned(), "thresholdSetter.controlReturned");
}
