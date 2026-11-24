// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

// -------------------------------------------------------------------------------------------------
// X Layer releaser parameters
//
// {smokeCheck} runs before the prerequisite script, {buildReplaceReleaserCall},
// {buildStartDecayCall} and {preflightXLayer} read these values, so none of them runs with an unset
// value.

/// @dev Record file shared by the prerequisite script and the proposal, at
///      `.records/<RECORD_NAME>.json`.
string constant RECORD_NAME = "XLayer";

/// @dev Keys in the record file, one per deployment.
library Records {
  string constant RELEASER = "XLayerReleaser";
  string constant THRESHOLD_SETTER = "DecayingThresholdSetter";
}

/// @dev X Layer parameters this proposal introduces. Addresses the proposal reads but does not
///      change come from govkit's `uniswap.xLayer`.
library XLayer {
  /// @dev The unified bridge on X Layer, the bridge the new releaser sends UNI through.
  ///      https://www.oklink.com/xlayer/address/0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe
  address constant TOKEN_BRIDGE = 0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe;

  /// @dev The UNI token the new releaser takes as its resource: the unified bridge's
  ///      wrapped UNI, which the bridge maps to UNI on Ethereum (network 0).
  ///      https://www.oklink.com/xlayer/address/0x2548C94A3092494dB3aF864cc2cF781a72f55678
  address constant RESOURCE = 0x2548C94A3092494dB3aF864cc2cF781a72f55678;

  /// @dev The new releaser's threshold at deployment and its {DecayingThresholdSetter}'s
  ///      `START_THRESHOLD`: 400,000 UNI, in wei of `RESOURCE`. {DecayingThresholdSetter-start}
  ///      requires the releaser's threshold to be at least `START_THRESHOLD`, so one constant
  ///      sets both. A start at `FLOOR_THRESHOLD` would release the TokenJar's fees to the first
  ///      searcher at a discount.
  uint256 constant START_THRESHOLD = 400_000e18;

  /// @dev The threshold at which the {DecayingThresholdSetter}'s decay ends: 2,000 UNI, in wei of
  ///      `RESOURCE`. It equals the threshold of the releaser the proposal replaces,
  ///      https://www.oklink.com/xlayer/address/0xe122E231cb52aea99690963Fd73E91e33E97468f
  uint256 constant FLOOR_THRESHOLD = 2000e18;

  /// @dev The time over which the {DecayingThresholdSetter} halves the threshold: 2 days.
  uint256 constant HALF_LIFE = 2 days;
}

/// @dev Asserts every proposal parameter is set.
function smokeCheck() pure {
  require(XLayer.TOKEN_BRIDGE != address(0), "XLayer.TOKEN_BRIDGE unset");
  require(XLayer.RESOURCE != address(0), "XLayer.RESOURCE unset");
  require(XLayer.START_THRESHOLD != 0, "XLayer.START_THRESHOLD unset");
  require(XLayer.FLOOR_THRESHOLD != 0, "XLayer.FLOOR_THRESHOLD unset");
  require(XLayer.HALF_LIFE != 0, "XLayer.HALF_LIFE unset");
}
