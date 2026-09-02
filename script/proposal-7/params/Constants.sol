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
/// `.records/HyperEVM.json`. The prerequisite script writes its deployments under the keys in
/// `Records` and the proposal reads them back.
string constant RECORD_NAME = "HyperEVM";

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
  /// govkit records this per destination chain on `EthereumBridgeSender`, but has no `hyperEvm`
  /// field yet, and reading a different chain's field for a HyperEVM message would misstate what
  /// the value is. It moves to the address book with the rest of HyperEVM after execution.
  address constant WORMHOLE_SENDER = 0xf5F4496219F31CDCBa6130B5402873624585615a;
}

library HyperEVM {
  /// @dev EIP-155 chain id.
  uint256 constant CHAIN_ID = 999;

  /// @dev Wormhole-defined chain id, which is not the EIP-155 one.
  ///
  /// source: `chainId()` on WORMHOLE_CORE returns 47, matching Wormhole's SDK constants.
  uint16 constant WORMHOLE_CHAIN_ID = 47;

  /// @dev Wormhole core bridge, deployed by Wormhole rather than by us.
  ///
  /// source: `chainId()` returns 47 and `getCurrentGuardianSetIndex()` returns 7.
  address constant WORMHOLE_CORE = 0x7C0faFc4384551f063e05aee704ab943b8B53aB3;

  /// @dev Uniswap V2 Factory on HyperEVM.
  ///
  /// TODO: pending the Uniswap protocol deployment on HyperEVM.
  address constant V2_FACTORY = address(0x00);

  /// @dev Uniswap V3 Factory on HyperEVM.
  ///
  /// TODO: pending the Uniswap protocol deployment on HyperEVM.
  address constant V3_FACTORY = address(0x00);

  /// @dev Uniswap V4 Pool Manager on HyperEVM.
  ///
  /// TODO: pending the Uniswap protocol deployment on HyperEVM.
  address constant POOL_MANAGER = address(0x00);

  /// @dev Governance-owned Wormhole message receiver on HyperEVM. Every contract deployed by the
  /// prerequisite scripts ends up owned by this address, and it is the account that executes the
  /// cross-chain half of the proposal.
  ///
  /// TODO: being deployed by the Uniswap protocol team.
  address constant WORMHOLE_RECEIVER = address(0x00);

  /// @dev Minimum amount of synthetic UNI a searcher must pay to claim the TokenJar's accumulated
  /// fees. BNB Chain uses 4000e18; Polygon and Robinhood Chain use 2000e18.
  ///
  /// TODO: awaiting a decision on the value for HyperEVM.
  uint256 constant RELEASER_THRESHOLD = 0;

  /// @dev Protocol fee that aggregator hook pools should end up charging, in pips (hundredths of
  /// a bip, so 1000 is 10 bps). Proposal 6 set 1000 on every chain but Base, which got 300.
  ///
  /// TODO: awaiting confirmation of which applies to HyperEVM.
  uint24 constant AGG_HOOK_FEE_PIPS = 0;

  /// @dev Value stored in `V4FeePolicy` for the aggregator hook family. Aggregator hooks multiply
  /// their assigned fee by 25 to get above the PoolManager's 10 bps cap, so the policy holds the
  /// intended fee divided by 25. Proposal 6 divides the same way; the division lives here so the
  /// undivided figure cannot be stored by mistake, since `V4FeePolicy` would accept it as valid.
  uint24 constant AGG_HOOK_DEFAULT_FEE = AGG_HOOK_FEE_PIPS / 25;

  /// @dev Protocol fee that stable-stable aggregator hook pools should end up charging, in pips.
  /// Proposal 6 set 300 on every chain but Base, which got 100. Applies to the pairs listed in
  /// `STABLE_STABLE_PAIRS_CSV`.
  ///
  /// TODO: awaiting confirmation of which applies to HyperEVM.
  uint24 constant STABLE_STABLE_FEE_PIPS = 0;

  /// @dev Value stored in `V4FeePolicy` for each stable-stable pair, divided by 25 for the reason
  /// given on `AGG_HOOK_DEFAULT_FEE`.
  uint24 constant STABLE_STABLE_FEE = STABLE_STABLE_FEE_PIPS / 25;

  /// @dev Hooks assigned to a fee family by address, read by `Lists.hookFamilies`. Header-only
  /// until HyperEVM hooks exist to list.
  string constant HOOK_FAMILIES_CSV = "script/proposal-7/params/hyperevm/hook-families.csv";

  /// @dev Stable-stable pairs, read by `Lists.stableStablePairs`. Header-only until the list is
  /// chosen.
  string constant STABLE_STABLE_PAIRS_CSV =
    "script/proposal-7/params/hyperevm/stable-stable-pairs.csv";
}

/// @dev Reverts unless every outstanding value above has been filled in.
function smokeCheck() pure {
  require(HyperEVM.V2_FACTORY != address(0x00), "HyperEVM.V2_FACTORY unset");
  require(HyperEVM.V3_FACTORY != address(0x00), "HyperEVM.V3_FACTORY unset");
  require(HyperEVM.POOL_MANAGER != address(0x00), "HyperEVM.POOL_MANAGER unset");
  require(HyperEVM.WORMHOLE_RECEIVER != address(0x00), "HyperEVM.WORMHOLE_RECEIVER unset");
  require(HyperEVM.RELEASER_THRESHOLD != 0, "HyperEVM.RELEASER_THRESHOLD unset");
  require(HyperEVM.AGG_HOOK_FEE_PIPS != 0, "HyperEVM.AGG_HOOK_FEE_PIPS unset");
  require(HyperEVM.STABLE_STABLE_FEE_PIPS != 0, "HyperEVM.STABLE_STABLE_FEE_PIPS unset");
}
