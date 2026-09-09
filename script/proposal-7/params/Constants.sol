// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

// -------------------------------------------------------------------------------------------------
// Addresses and parameters for proposal 7.
//
// New chains live here first and move to govkit's address book only once the proposal activating
// them has executed onchain, so nothing about an unannounced deployment reaches a public repo
// ahead of the vote. Proposal 5 did the same for Robinhood Chain.
//
// `smokeCheck` is called at the top of every proposal 7 script, so no script can run against a
// value that is still outstanding.

/// @dev Record file shared by the prerequisite script and the proposal, at
/// `.records/Arc.json`. The prerequisite script writes its deployments under the keys in
/// `Records` and the proposal reads them back.
string constant RECORD_NAME = "Arc";

/// @dev Keys in the record file, one per deployment.
library Records {
  string constant SYNTHETIC_NTT_UNI = "SyntheticNttUni";
  string constant NTT_MANAGER_IMPLEMENTATION = "NttManagerImplementation";
  string constant NTT_MANAGER = "NttManager";
  string constant WORMHOLE_TRANSCEIVER_IMPLEMENTATION = "WormholeTransceiverImplementation";
  string constant WORMHOLE_TRANSCEIVER = "WormholeTransceiver";

  string constant TOKEN_JAR = "TokenJar";
  string constant RELEASER = "Releaser";
  string constant V3_OPEN_FEE_ADAPTER = "V3OpenFeeAdapter";
  string constant V4_FEE_ADAPTER = "V4FeeAdapter";
  string constant V4_FEE_POLICY = "V4FeePolicy";
}

library Ethereum {
  /// @dev Uniswap's Wormhole sender, owned by the Timelock. Shared across every Wormhole-bridged
  /// chain; the destination is a parameter of `sendMessage`, not a property of the sender.
  ///
  /// govkit records this per destination chain on `EthereumBridgeSender`, but has no `arc`
  /// field yet, and reading a different chain's field for a Arc message would misstate what
  /// the value is. It moves to the address book with the rest of Arc after execution.
  address constant WORMHOLE_SENDER = 0xf5F4496219F31CDCBa6130B5402873624585615a;
}

library Arc {
  /// @dev EIP-155 chain id.
  ///
  /// source: `eth_chainId` on Arc mainnet returns 5042; briefcase records the deployments below
  /// under `deployments/5042.json`.
  uint256 constant CHAIN_ID = 5042;

  /// @dev Wormhole-defined chain id, which is not the EIP-155 one.
  ///
  /// source: `chainId()` on WORMHOLE_CORE returns 71, matching Wormhole's SDK constants.
  uint16 constant WORMHOLE_CHAIN_ID = 71;

  /// @dev Wormhole core bridge, deployed by Wormhole rather than by us.
  ///
  /// source: Wormhole's SDK constants for Arc mainnet; `chainId()` returns 71,
  /// `evmChainId()` returns 5042, and `getCurrentGuardianSetIndex()` returns 7.
  address constant WORMHOLE_CORE = 0xC8aD24fC6063c41cB5C12a8e3851AafC3b3CF027;

  /// @dev Uniswap V2 Factory on Arc.
  ///
  /// source: briefcase `deployments/5042.json` from v0.1.60. Not the canonical v2 factory
  /// address, which has no code on Arc.
  address constant V2_FACTORY = 0x89e5DB8B5aA49aA85AC63f691524311AEB649eba;

  /// @dev Uniswap V3 Factory on Arc.
  ///
  /// source: briefcase `deployments/5042.json` from v0.1.60.
  address constant V3_FACTORY = 0xf0db7b58379503491d857dB50AC9ece64c653918;

  /// @dev Uniswap V4 Pool Manager on Arc.
  ///
  /// source: briefcase `deployments/5042.json` from v0.1.60.
  address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;

  /// @dev Governance-owned Wormhole message receiver on Arc. Every contract deployed by the
  /// prerequisite scripts ends up owned by this address, and it is the account that executes the
  /// cross-chain half of the proposal.
  ///
  /// TODO: not yet deployed. A 3-of-5 Safe, `0x33F26c5d69E2c40956f22c6195B6A499cF4151E8`, holds
  /// the v2 `feeToSetter`, the v3 `owner`, and the `PoolManager` `owner` until the receiver
  /// exists and the Safe hands them over. `preflightArc()` asserts that handoff.
  address constant WORMHOLE_RECEIVER = address(0x00);

  /// @dev Minimum amount of synthetic UNI a searcher must pay to claim the TokenJar's accumulated
  /// fees. BNB Chain uses 4000e18; Polygon and Robinhood Chain use 2000e18.
  ///
  /// TODO: awaiting a decision on the value for Arc.
  uint256 constant RELEASER_THRESHOLD = 0;

  /// @dev Protocol fee that aggregator hook pools should end up charging, in pips (hundredths of
  /// a bip, so 1000 is 10 bps). Proposal 6 set 1000 on every chain but Base, which got 300. The
  /// script stores it through `FeeSchedule.aggHookFeeValue`, which applies the aggregator
  /// multiplier.
  ///
  /// TODO: awaiting confirmation of which applies to Arc.
  uint24 constant AGG_HOOK_FEE_PIPS = 0;

  /// @dev Per-chain `V4FeePolicy` assignments, hook families and pair-class fees, read for this
  /// chain by `V4FeePolicyAssignments`. Both lists are empty until Arc hooks exist to list
  /// and the stable-stable pairs and their fee are chosen.
  string constant V4_FEE_POLICY_JSON = "script/proposal-7/params/v4-fee-policy.json";
}

/// @dev Reverts unless every outstanding value above has been filled in.
function smokeCheck() pure {
  require(Arc.WORMHOLE_RECEIVER != address(0x00), "Arc.WORMHOLE_RECEIVER unset");
  require(Arc.RELEASER_THRESHOLD != 0, "Arc.RELEASER_THRESHOLD unset");
  require(Arc.AGG_HOOK_FEE_PIPS != 0, "Arc.AGG_HOOK_FEE_PIPS unset");
}
