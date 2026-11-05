// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

// -------------------------------------------------------------------------------------------------
// X Layer releaser parameters
//
// `smokeCheck` runs before the prerequisite script, `buildReplaceReleaserCall` and
// `preflightXLayer` read any of these values, so none of them can run against a value that is still
// outstanding.

/// @dev Record file shared by the prerequisite script and the proposal, at
///      `.records/<RECORD_NAME>.json`.
string constant RECORD_NAME = "XLayer";

/// @dev Keys in the record file, one per deployment.
library Records {
  string constant RELEASER = "AggLayerReleaser";
}

/// @dev X Layer parameters this proposal introduces. Addresses the proposal reads but does not
///      change come from govkit's `uniswap.xLayer`.
library XLayer {
  /// @dev The AggLayer unified bridge on X Layer, the bridge the new releaser sends UNI through.
  ///      https://www.oklink.com/xlayer/address/0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe
  address constant TOKEN_BRIDGE = 0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe;

  /// @dev The UNI token the new releaser takes as its resource: the AggLayer unified bridge's
  ///      wrapped UNI, which the bridge maps to UNI on Ethereum (network 0).
  ///      https://www.oklink.com/xlayer/address/0x2548C94A3092494dB3aF864cc2cF781a72f55678
  address constant RESOURCE = 0x2548C94A3092494dB3aF864cc2cF781a72f55678;

  /// @dev The amount of `RESOURCE` the new releaser takes per release when deployed, in wei. A
  ///      decaying threshold setter lowers it toward 2,000 UNI; starting at 2,000 UNI would hand
  ///      the TokenJar's accumulated fees to the first searcher at a discount.
  uint256 constant INITIAL_THRESHOLD = 60_000e18;
}

/// @dev Asserts every proposal parameter is set.
function smokeCheck() pure {
  require(XLayer.TOKEN_BRIDGE != address(0), "XLayer.TOKEN_BRIDGE unset");
  require(XLayer.RESOURCE != address(0), "XLayer.RESOURCE unset");
  require(XLayer.INITIAL_THRESHOLD != 0, "XLayer.INITIAL_THRESHOLD unset");
}
