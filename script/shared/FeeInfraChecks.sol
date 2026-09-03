// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.29;

import {TokenJar} from "../../src/TokenJar.sol";
import {V3OpenFeeAdapter} from "../../src/feeAdapters/V3OpenFeeAdapter.sol";
import {V4FeeAdapter} from "../../src/feeAdapters/V4FeeAdapter.sol";
import {V4FeePolicy} from "../../src/feeAdapters/V4FeePolicy.sol";
import {IReleaser} from "../../src/interfaces/IReleaser.sol";
import {IOwned} from "../../src/interfaces/base/IOwned.sol";
import {PairClassFeeAssignment} from "../../src/interfaces/IV4FeePolicy.sol";
import {
  FeeInfraParams,
  V3_TIER_100,
  V3_TIER_500,
  V3_TIER_3000,
  V3_TIER_10000
} from "./FeeInfraParams.sol";
import {FeeSchedule} from "./FeeSchedule.sol";

/// @dev What a fee infra deployment produced, however it was deployed.
struct FeeInfraAddresses {
  TokenJar tokenJar;
  IReleaser releaser;
  V3OpenFeeAdapter v3OpenFeeAdapter;
  V4FeeAdapter v4FeeAdapter;
  V4FeePolicy v4FeePolicy;
}

/// @dev Asserts that a fee infra deployment matches the params it was given. The struct that
/// drove the deployment is the oracle for the check, so the two cannot drift, and the check does
/// not care whether a script or a deployer contract did the deploying.
///
/// The releaser is checked through `IReleaser` only; its bridge-specific wiring is the bridge's
/// checks to cover. Every assertion names the field it checks, so a failure reads as the field
/// that is wrong.
library FeeInfraChecks {
  function check(FeeInfraAddresses memory a, FeeInfraParams memory p) internal view {
    // TokenJar
    require(a.tokenJar.releaser() == address(a.releaser), "tokenJar.releaser");
    require(a.tokenJar.owner() == p.receiver, "tokenJar.owner");

    // Releaser
    require(address(a.releaser.TOKEN_JAR()) == address(a.tokenJar), "releaser.tokenJar");
    require(a.releaser.threshold() == p.releaserThreshold, "releaser.threshold");
    require(a.releaser.thresholdSetter() == p.receiver, "releaser.thresholdSetter");
    require(IOwned(address(a.releaser)).owner() == p.receiver, "releaser.owner");

    // V3OpenFeeAdapter
    require(address(a.v3OpenFeeAdapter.FACTORY()) == p.v3Factory, "v3OpenFeeAdapter.factory");
    require(a.v3OpenFeeAdapter.TOKEN_JAR() == address(a.tokenJar), "v3OpenFeeAdapter.tokenJar");
    require(a.v3OpenFeeAdapter.defaultFee() == p.v3DefaultFee, "v3OpenFeeAdapter.defaultFee");
    require(
      a.v3OpenFeeAdapter.feeTierDefaults(V3_TIER_100) == p.v3FeeTierDefaults[0],
      "v3OpenFeeAdapter.feeTierDefault.100"
    );
    require(
      a.v3OpenFeeAdapter.feeTierDefaults(V3_TIER_500) == p.v3FeeTierDefaults[1],
      "v3OpenFeeAdapter.feeTierDefault.500"
    );
    require(
      a.v3OpenFeeAdapter.feeTierDefaults(V3_TIER_3000) == p.v3FeeTierDefaults[2],
      "v3OpenFeeAdapter.feeTierDefault.3000"
    );
    require(
      a.v3OpenFeeAdapter.feeTierDefaults(V3_TIER_10000) == p.v3FeeTierDefaults[3],
      "v3OpenFeeAdapter.feeTierDefault.10000"
    );

    // `feeTiers` is a public array with no length getter, so the four tiers are checked by index.
    // `storeFeeTier` rejects duplicates but is permissionless, so a longer array is possible and
    // harmless: `triggerFeeUpdate` walks it and every entry resolves through the defaults above.
    require(a.v3OpenFeeAdapter.feeTiers(0) == V3_TIER_100, "v3OpenFeeAdapter.feeTiers.0");
    require(a.v3OpenFeeAdapter.feeTiers(1) == V3_TIER_500, "v3OpenFeeAdapter.feeTiers.1");
    require(a.v3OpenFeeAdapter.feeTiers(2) == V3_TIER_3000, "v3OpenFeeAdapter.feeTiers.2");
    require(a.v3OpenFeeAdapter.feeTiers(3) == V3_TIER_10000, "v3OpenFeeAdapter.feeTiers.3");

    require(a.v3OpenFeeAdapter.feeSetter() == p.receiver, "v3OpenFeeAdapter.feeSetter");
    require(a.v3OpenFeeAdapter.owner() == p.receiver, "v3OpenFeeAdapter.owner");

    // V4FeeAdapter
    require(address(a.v4FeeAdapter.POOL_MANAGER()) == p.poolManager, "v4FeeAdapter.poolManager");
    require(a.v4FeeAdapter.TOKEN_JAR() == address(a.tokenJar), "v4FeeAdapter.tokenJar");
    require(address(a.v4FeeAdapter.policy()) == address(a.v4FeePolicy), "v4FeeAdapter.policy");
    require(a.v4FeeAdapter.feeSetter() == p.receiver, "v4FeeAdapter.feeSetter");
    require(a.v4FeeAdapter.owner() == p.receiver, "v4FeeAdapter.owner");

    // V4FeePolicy
    require(address(a.v4FeePolicy.POOL_MANAGER()) == p.poolManager, "v4FeePolicy.poolManager");

    // Nothing sets the global default, and leaving it at zero is deliberate: a non-zero value
    // would charge every v4 pool, not just the aggregator family.
    require(a.v4FeePolicy.defaultFee() == 0, "v4FeePolicy.defaultFee");

    require(a.v4FeePolicy.feeBucketsLength() == p.feeBuckets.length, "v4FeePolicy.feeBucketsLength");
    require(a.v4FeePolicy.flagRulesLength() == p.flagRules.length, "v4FeePolicy.flagRulesLength");
    require(
      a.v4FeePolicy.familyDefaults(p.aggHookFamilyId) == p.aggHookDefaultFee,
      "v4FeePolicy.familyDefaults"
    );
    require(a.v4FeePolicy.feeSetter() == p.receiver, "v4FeePolicy.feeSetter");
    require(a.v4FeePolicy.owner() == p.receiver, "v4FeePolicy.owner");

    for (uint256 i; i < p.feeBuckets.length; i++) {
      (uint24 lpFeeFloor, uint24 alphaPips, uint32 betaPips) = a.v4FeePolicy.feeBucket(i);
      require(lpFeeFloor == p.feeBuckets[i].lpFeeFloor, "v4FeePolicy.feeBucket.lpFeeFloor");
      require(alphaPips == p.feeBuckets[i].alphaPips, "v4FeePolicy.feeBucket.alphaPips");
      require(betaPips == p.feeBuckets[i].betaPips, "v4FeePolicy.feeBucket.betaPips");
    }

    for (uint256 i; i < p.flagRules.length; i++) {
      (uint256 requiredFlags, uint8 familyId) = a.v4FeePolicy.flagRules(i);
      require(requiredFlags == p.flagRules[i].requiredFlags, "v4FeePolicy.flagRules.requiredFlags");
      require(familyId == p.flagRules[i].familyId, "v4FeePolicy.flagRules.familyId");
    }

    for (uint256 i; i < p.hookFamilies.length; i++) {
      require(
        a.v4FeePolicy.hookFamilyId(p.hookFamilies[i].hook) == p.hookFamilies[i].familyId,
        "v4FeePolicy.hookFamilyId"
      );
    }

    for (uint256 i; i < p.pairClassFees.length; i++) {
      PairClassFeeAssignment memory f = p.pairClassFees[i];
      require(
        a.v4FeePolicy.pairClassFees(FeeSchedule.pairHash(f.currency0, f.currency1), f.familyId)
          == f.feeValue,
        "v4FeePolicy.pairClassFees"
      );
    }
  }
}
