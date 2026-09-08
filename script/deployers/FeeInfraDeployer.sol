// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {TokenJar} from "../../src/TokenJar.sol";
import {V3OpenFeeAdapter} from "../../src/feeAdapters/V3OpenFeeAdapter.sol";
import {V4FeeAdapter} from "../../src/feeAdapters/V4FeeAdapter.sol";
import {V4FeePolicy} from "../../src/feeAdapters/V4FeePolicy.sol";
import {IReleaser} from "../../src/interfaces/IReleaser.sol";
import {IOwned} from "../../src/interfaces/base/IOwned.sol";
import {
  FeeInfraParams,
  V3_TIER_100,
  V3_TIER_500,
  V3_TIER_3000,
  V3_TIER_10000
} from "../shared/FeeInfraParams.sol";

// -------------------------------------------------------------------------------------------------
// Brings a chain into the fee ecosystem from a constructor, so that what proposal 4 did in
// thirty-two transactions happens in one: the TokenJar, the releaser, the v3 and v4 adapters and
// the v4 policy, their configuration, and handover to governance. The same on every chain except
// for the releaser, which depends on how UNI gets back to Ethereum, so a bridge-specific subclass
// supplies it through `_deployReleaser` and calls `_deployFeeInfra` from its own constructor,
// after whatever infrastructure the releaser needs.
//
// Two properties follow from being a constructor. Nothing is left half-configured: a revert
// anywhere undoes everything. And no account other than this contract ever holds authority over
// the deployed contracts, and this contract holds it only until its constructor returns; the
// interim fee setter is `address(this)`, and every contract is handed to `receiver` before the
// constructor ends.
//
// Every deployment uses CREATE2 with a fixed salt, so the addresses are a function of this
// contract's address alone. The addresses are left in public storage for the script to check
// and record.
//
// Steps are labelled `F.00` onward, the fee phase of a deployment, so a chain's index can refer
// to them.
//
abstract contract FeeInfraDeployer {
  bytes32 constant SALT_TOKEN_JAR = bytes32(uint256(1));
  bytes32 constant SALT_RELEASER = bytes32(uint256(2));
  bytes32 constant SALT_V3_OPEN_FEE_ADAPTER = bytes32(uint256(3));
  bytes32 constant SALT_V4_FEE_ADAPTER = bytes32(uint256(4));
  bytes32 constant SALT_V4_FEE_POLICY = bytes32(uint256(5));

  TokenJar public tokenJar;
  IReleaser public releaser;
  V3OpenFeeAdapter public v3OpenFeeAdapter;
  V4FeeAdapter public v4FeeAdapter;
  V4FeePolicy public v4FeePolicy;

  /// @dev Deploys the releaser for this chain's bridge, pointed at `_tokenJar`. Step F.01. This
  /// contract configures and hands over whatever comes back through `IReleaser`; anything
  /// specific to the releaser's bridge is the subclass's to build and the script's to check.
  ///
  /// Subclasses should deploy with `SALT_RELEASER` so the releaser's address is as predictable as
  /// the rest.
  function _deployReleaser(address _tokenJar, uint256 _threshold)
    internal
    virtual
    returns (IReleaser);

  /// @dev Steps F.00 through F.31.
  function _deployFeeInfra(FeeInfraParams memory p) internal {
    // -----------------------------------------------------------------------------------------
    // F.00
    //
    // Deploy `TokenJar`.
    //
    tokenJar = new TokenJar{salt: SALT_TOKEN_JAR}();

    // -----------------------------------------------------------------------------------------
    // F.01
    //
    // Deploy the releaser, through the bridge-specific `_deployReleaser`.
    //
    // Parameters:
    //
    // - `_tokenJar`: `TokenJar`.
    // - `_threshold`: Minimum amount of the releaser's resource required to release.
    //
    releaser = _deployReleaser({_tokenJar: address(tokenJar), _threshold: p.releaserThreshold});

    // -----------------------------------------------------------------------------------------
    // F.02
    //
    // Set the releaser on `TokenJar`.
    //
    tokenJar.setReleaser({_releaser: address(releaser)});

    // -----------------------------------------------------------------------------------------
    // F.03
    //
    // Transfer `TokenJar` ownership to governance.
    //
    tokenJar.transferOwnership({newOwner: p.receiver});

    // -----------------------------------------------------------------------------------------
    // F.04
    //
    // Set the releaser's threshold-setter to governance.
    //
    releaser.setThresholdSetter({newThresholdSetter: p.receiver});

    // -----------------------------------------------------------------------------------------
    // F.05
    //
    // Transfer ownership of the releaser to governance.
    //
    // The releaser needs no further configuration, so it is handed over as soon as the TokenJar
    // knows about it. Each contract below stays with this deployer only for as long as its own
    // configuration requires.
    //
    IOwned(address(releaser)).transferOwnership({newOwner: p.receiver});

    // -----------------------------------------------------------------------------------------
    // F.06
    //
    // Deploy `V3OpenFeeAdapter`.
    //
    // Parameters:
    //
    // - `_factory`: This chain's Uniswap V3 Factory.
    // - `_tokenJar`: `TokenJar`.
    //
    v3OpenFeeAdapter = new V3OpenFeeAdapter{salt: SALT_V3_OPEN_FEE_ADAPTER}({
      _factory: p.v3Factory, _tokenJar: address(tokenJar)
    });

    // -----------------------------------------------------------------------------------------
    // F.07
    //
    // Set `V3OpenFeeAdapter` fee-setter to this deployer for configuration.
    //
    // A script would name the deployer by reading the adapter's `owner()`, because a script's
    // `msg.sender` need not be its broadcaster. Here the two coincide: this contract deployed the
    // adapter, so it is the owner, and it is the caller of every configuration call below.
    //
    v3OpenFeeAdapter.setFeeSetter({newFeeSetter: address(this)});

    // -----------------------------------------------------------------------------------------
    // F.08
    //
    // Set `V3OpenFeeAdapter` default fee.
    //
    v3OpenFeeAdapter.setDefaultFee({feeValue: p.v3DefaultFee});

    // -----------------------------------------------------------------------------------------
    // F.09, F.10, F.11, F.12
    //
    // Set `V3OpenFeeAdapter` fee tier defaults.
    //
    // Parameters:
    //
    // - `feeTier`: Fee tier to set.
    // - `feeValue`: Default fee value for the tier.
    //
    v3OpenFeeAdapter.setFeeTierDefault({feeTier: V3_TIER_100, feeValue: p.v3FeeTierDefaults[0]});
    v3OpenFeeAdapter.setFeeTierDefault({feeTier: V3_TIER_500, feeValue: p.v3FeeTierDefaults[1]});
    v3OpenFeeAdapter.setFeeTierDefault({feeTier: V3_TIER_3000, feeValue: p.v3FeeTierDefaults[2]});
    v3OpenFeeAdapter.setFeeTierDefault({feeTier: V3_TIER_10000, feeValue: p.v3FeeTierDefaults[3]});

    // -----------------------------------------------------------------------------------------
    // F.13, F.14, F.15, F.16
    //
    // Store `V3OpenFeeAdapter` fee tiers, the tiers `triggerFeeUpdate` walks.
    //
    v3OpenFeeAdapter.storeFeeTier({feeTier: V3_TIER_100});
    v3OpenFeeAdapter.storeFeeTier({feeTier: V3_TIER_500});
    v3OpenFeeAdapter.storeFeeTier({feeTier: V3_TIER_3000});
    v3OpenFeeAdapter.storeFeeTier({feeTier: V3_TIER_10000});

    // -----------------------------------------------------------------------------------------
    // F.17, F.18
    //
    // Transfer `V3OpenFeeAdapter` fee-setter permission, then ownership, to governance.
    //
    v3OpenFeeAdapter.setFeeSetter({newFeeSetter: p.receiver});
    v3OpenFeeAdapter.transferOwnership({newOwner: p.receiver});

    // -----------------------------------------------------------------------------------------
    // F.19
    //
    // Deploy `V4FeeAdapter`.
    //
    // V4 splits the two contracts: the adapter is what the `PoolManager` calls as its protocol
    // fee controller, and the policy holds the fee schedule the adapter reads.
    //
    // Parameters:
    //
    // - `poolManager`: This chain's Uniswap V4 Pool Manager.
    // - `tokenJar`: `TokenJar`.
    //
    v4FeeAdapter = new V4FeeAdapter{salt: SALT_V4_FEE_ADAPTER}({
      poolManager: IPoolManager(p.poolManager), tokenJar: address(tokenJar)
    });

    // -----------------------------------------------------------------------------------------
    // F.20
    //
    // Deploy `V4FeePolicy`.
    //
    v4FeePolicy =
      new V4FeePolicy{salt: SALT_V4_FEE_POLICY}({poolManager: IPoolManager(p.poolManager)});

    // -----------------------------------------------------------------------------------------
    // F.21
    //
    // Set `V4FeePolicy` on `V4FeeAdapter`.
    //
    v4FeeAdapter.setPolicy(v4FeePolicy);

    // -----------------------------------------------------------------------------------------
    // F.22
    //
    // Set `V4FeePolicy` fee-setter to this deployer for configuration. Same reasoning as F.07.
    //
    v4FeePolicy.setFeeSetter(address(this));

    // -----------------------------------------------------------------------------------------
    // F.23
    //
    // Set `V4FeePolicy` fee buckets.
    //
    v4FeePolicy.setFeeBuckets(p.feeBuckets);

    // -----------------------------------------------------------------------------------------
    // F.24
    //
    // Set `V4FeePolicy` flag rules.
    //
    v4FeePolicy.setFlagRules(p.flagRules);

    // -----------------------------------------------------------------------------------------
    // F.25
    //
    // Set `V4FeePolicy` aggregator hook family default.
    //
    v4FeePolicy.setFamilyDefault({familyId: p.aggHookFamilyId, feeValue: p.aggHookDefaultFee});

    // -----------------------------------------------------------------------------------------
    // F.26
    //
    // Assign `V4FeePolicy` hook families by address. Skipped while the list is empty.
    //
    if (p.hookFamilies.length > 0) v4FeePolicy.batchSetHookFamily(p.hookFamilies);

    // -----------------------------------------------------------------------------------------
    // F.27
    //
    // Set `V4FeePolicy` pair-level fees for the aggregator hook family. Skipped while the list is
    // empty.
    //
    if (p.pairClassFees.length > 0) v4FeePolicy.batchSetPairClassFee(p.pairClassFees);

    // -----------------------------------------------------------------------------------------
    // F.28, F.29
    //
    // Transfer `V4FeePolicy` fee-setter permission, then ownership, to governance.
    //
    v4FeePolicy.setFeeSetter(p.receiver);
    v4FeePolicy.transferOwnership(p.receiver);

    // -----------------------------------------------------------------------------------------
    // F.30, F.31
    //
    // Transfer `V4FeeAdapter` fee-setter permission, then ownership, to governance.
    //
    v4FeeAdapter.setFeeSetter(p.receiver);
    v4FeeAdapter.transferOwnership(p.receiver);
  }
}
