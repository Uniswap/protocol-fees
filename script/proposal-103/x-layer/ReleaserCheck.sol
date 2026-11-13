// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Uniswap} from "govkit/types/Uniswap.sol";

import {AggLayerReleaser} from "../../../src/releasers/AggLayerReleaser.sol";
import {IAggLayerBridge} from "../../../src/interfaces/external/IAggLayerBridge.sol";
import {XLayer} from "./Constants.sol";

/// @dev Asserts `releaser` answers as the releaser the prerequisite script deploys: an
///      `AggLayerReleaser` that sends `XLayer.RESOURCE` to Ethereum through `XLayer.TOKEN_BRIDGE`,
///      releases from the X Layer TokenJar at `XLayer.INITIAL_THRESHOLD`, and answers to the
///      CrossChainAccount. The prerequisite script runs it on its own deployment, and
///      `preflightXLayer` runs it on the recorded deployment. It reads getters and does not compare
///      code, so it cannot tell the audited releaser from a contract that answers the same way.
function checkNewReleaser(Uniswap storage uniswap, address releaser) view {
  require(releaser.code.length != 0, "newReleaser.code");
  AggLayerReleaser newReleaser = AggLayerReleaser(releaser);

  // Assert the constructor arguments. The releaser checks the bridge's mapping of its resource on
  // every release, but it trusts `BRIDGE` to answer truthfully, so only this check pins the
  // bridge itself.
  require(address(newReleaser.BRIDGE()) == XLayer.TOKEN_BRIDGE, "newReleaser.BRIDGE");
  require(address(newReleaser.RESOURCE()) == XLayer.RESOURCE, "newReleaser.RESOURCE");
  require(newReleaser.L1_RESOURCE() == uniswap.ethereum.uni, "newReleaser.L1_RESOURCE");
  require(address(newReleaser.TOKEN_JAR()) == uniswap.xLayer.tokenJar, "newReleaser.TOKEN_JAR");
  require(newReleaser.RESOURCE_RECIPIENT() == releaser, "newReleaser.RESOURCE_RECIPIENT");
  require(newReleaser.threshold() == XLayer.INITIAL_THRESHOLD, "newReleaser.threshold");

  // Assert the handoff.
  require(newReleaser.owner() == uniswap.xLayer.crossChainAccount, "newReleaser.owner");
  require(
    newReleaser.thresholdSetter() == uniswap.xLayer.crossChainAccount, "newReleaser.thresholdSetter"
  );

  // Assert the bridge maps the resource to UNI on Ethereum, so releases do not revert with
  // `ResourceNotWrappedL1Resource`.
  (uint32 originNetwork, address originTokenAddress) =
    IAggLayerBridge(XLayer.TOKEN_BRIDGE).wrappedTokenToTokenInfo(XLayer.RESOURCE);
  require(
    originNetwork == newReleaser.AGGLAYER_ETHEREUM_NETWORK_ID(), "bridge.resource.originNetwork"
  );
  require(originTokenAddress == uniswap.ethereum.uni, "bridge.resource.originTokenAddress");
}
