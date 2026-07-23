// SPDX-License-Identifier: AGPl-3.0-only
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {InboxEncoder} from "govkit/bridges/InboxEncoder.sol";

import {V4FeeAdapter} from "../../../src/feeAdapters/V4FeeAdapter.sol";
import {V4FeePolicy} from "../../../src/feeAdapters/V4FeePolicy.sol";
import {
  FeeBucket,
  FlagRule,
  FamilyDefaultAssignment,
  PairClassFeeAssignment,
  HookFamilyAssignment
} from "../../../src/interfaces/IV4FeePolicy.sol";
import {StableStablePairs} from "../../proposal-6/StableStablePairs.sol";

import "../../proposal-5/Constants.sol" as Constants;

import {AGG_HOOK_FAMILY, AGG_HOOK_ID, NATIVE_MATH_ID, FamilyTiers} from "../FamilyConstants.sol";

/// @notice Deploys and fully configures the tiered fee adapter + policy on every chain, then
/// hands authority to governance. The tiered pair goes live only when governance repoints
/// `PoolManager.setProtocolFeeController` at the tiered adapter (see V4FeesUpgradeProposal),
/// so nothing here is reachable by pools until the proposal executes.
///
/// Tiered configuration = exact replica of the live original policy (verified against live
/// state in the checks below) + the self-opt-in fee tier families and the native-math
/// opt-in flag rule. The tiered contracts also carry the batch setters from PR review.
contract DeployTieredV4FeeInfra is Script {
  Recorder internal recorder;
  Recorder internal originalRecorder;
  Uniswap internal uniswap;
  StableStablePairs internal stableStablePairs;

  function run() external {
    uniswap.loadLatest();
    recorder.initialize("DeployTieredV4FeeInfra");
    originalRecorder.initialize("DeployV4FeeInfra");
    stableStablePairs.initialize();

    address scriptRunnerEoa = msg.sender;
    uint256 chainId = block.chainid;

    (address poolManager, address tokenJar, address postConfigOwner) = getAddresses(chainId);

    if (chainId == Constants.Robinhood.CHAIN_ID) {
      require(Constants.Robinhood.TOKEN_JAR != address(0x00));
    }

    vm.startBroadcast();

    // -----------------------------------------------------------------------------------------
    // Deploy V4FeeAdapter (tiered)
    //
    V4FeeAdapter adapter;
    if (!recorder.exists(chainId, "V4FeeAdapterTiered")) {
      adapter = new V4FeeAdapter({poolManager: IPoolManager(poolManager), tokenJar: tokenJar});

      recorder.write({
        chainId: chainId, deploymentName: "V4FeeAdapterTiered", deployment: address(adapter)
      });
    } else {
      adapter = V4FeeAdapter(recorder.read(chainId, "V4FeeAdapterTiered"));
    }

    // -----------------------------------------------------------------------------------------
    // Deploy V4FeePolicy (tiered)
    //
    V4FeePolicy policy;
    if (!recorder.exists(chainId, "V4FeePolicyTiered")) {
      policy = new V4FeePolicy({poolManager: IPoolManager(poolManager)});

      recorder.write({
        chainId: chainId, deploymentName: "V4FeePolicyTiered", deployment: address(policy)
      });
    } else {
      policy = V4FeePolicy(recorder.read(chainId, "V4FeePolicyTiered"));
    }

    // -----------------------------------------------------------------------------------------
    // Set Policy on Adapter
    //
    adapter.setPolicy(policy);

    // -----------------------------------------------------------------------------------------
    // Take Fee Setter Authority
    //
    policy.setFeeSetter(scriptRunnerEoa);

    // -----------------------------------------------------------------------------------------
    // Assign Fee Buckets (identical to the original)
    //
    FeeBucket[] memory feeBuckets = new FeeBucket[](8);
    feeBuckets[0] = FeeBucket({lpFeeFloor: 0, alphaPips: 1, betaPips: 0});
    feeBuckets[1] = FeeBucket({lpFeeFloor: 3, alphaPips: 1, betaPips: 263_889});
    feeBuckets[2] = FeeBucket({lpFeeFloor: 75, alphaPips: 20, betaPips: 200_000});
    feeBuckets[3] = FeeBucket({lpFeeFloor: 100, alphaPips: 25, betaPips: 272_728});
    feeBuckets[4] = FeeBucket({lpFeeFloor: 375, alphaPips: 100, betaPips: 200_000});
    feeBuckets[5] = FeeBucket({lpFeeFloor: 500, alphaPips: 125, betaPips: 137_500});
    feeBuckets[6] = FeeBucket({lpFeeFloor: 2500, alphaPips: 400, betaPips: 200_000});
    feeBuckets[7] = FeeBucket({lpFeeFloor: 5500, alphaPips: 1000, betaPips: 0});
    policy.setFeeBuckets(feeBuckets);

    // -----------------------------------------------------------------------------------------
    // Set Flag Rules (original aggregator rule + tier families + native-math opt-in)
    //
    // | Name             | ID        | Flags      |
    // | ---------------- | --------- | ---------- |
    // | Aggregator Hooks | `11`      | `1 << 11`  |
    // | Tier Families    | `20`-`31` | `1 << id` (see FamilyConstants.sol) |
    // | Native Math      | `255`     | `1 << 255` |
    //
    policy.setFlagRules(FamilyTiers.flagRules());

    // -----------------------------------------------------------------------------------------
    // Set Aggregator Hook Fees (identical to the original)
    //
    {
      uint24 defaultFeeValue = (chainId == ChainId.Base ? 300 : 1000) / 25;
      uint24 stableStableFeeValue = (chainId == ChainId.Base ? 100 : 300) / 25;

      policy.setFamilyDefault({familyId: AGG_HOOK_ID, feeValue: encodeFee(defaultFeeValue)});

      uint256 length = stableStablePairs.chainPairs[chainId].length;

      PairClassFeeAssignment[] memory assignments = new PairClassFeeAssignment[](length);
      for (uint256 i; i < length; i++) {
        address token0 = stableStablePairs.chainPairs[chainId][i].token0;
        address token1 = stableStablePairs.chainPairs[chainId][i].token1;

        (token0, token1) = sort(token0, token1);

        assignments[i] = PairClassFeeAssignment({
          currency0: Currency.wrap(token0),
          currency1: Currency.wrap(token1),
          familyId: AGG_HOOK_ID,
          feeValue: encodeFee(stableStableFeeValue)
        });
      }
      policy.batchSetPairClassFee(assignments);
    }

    // -----------------------------------------------------------------------------------------
    // Set Tier Family Defaults
    //
    policy.batchSetFamilyDefault(FamilyTiers.familyDefaults());

    // -----------------------------------------------------------------------------------------
    // Set LBP & CCA Hooks (identical to the original)
    //
    {
      HookFamilyAssignment[] memory assignments = hookAssignments(chainId);
      if (assignments.length > 0) policy.batchSetHookFamily(assignments);
    }

    // -----------------------------------------------------------------------------------------
    // Transfer Authority
    //
    policy.setFeeSetter(postConfigOwner);

    policy.transferOwnership(postConfigOwner);

    adapter.setFeeSetter(postConfigOwner);

    adapter.transferOwnership(postConfigOwner);

    vm.stopBroadcast();

    // -----------------------------------------------------------------------------------------
    // Run Checks
    //
    console.log("Checking ...");

    require(address(adapter.POOL_MANAGER()) == poolManager);
    require(adapter.TOKEN_JAR() == tokenJar);
    require(adapter.feeSetter() == postConfigOwner);
    require(address(adapter.policy()) == address(policy));

    require(address(policy.POOL_MANAGER()) == poolManager);
    require(policy.feeSetter() == postConfigOwner);
    require(policy.defaultFee() == 0);
    require(!policy.isHookedNativeMathFeeOn());

    // New config: aggregator rule first, tiers descending, native-math opt-in last.
    require(policy.flagRulesLength() == 2 + FamilyTiers.TIER_COUNT);
    {
      (uint256 flags, uint8 familyId) = policy.flagRules(0);
      require(flags == AGG_HOOK_FAMILY && familyId == AGG_HOOK_ID);

      for (uint256 i; i < FamilyTiers.TIER_COUNT; i++) {
        uint8 expectedId = FamilyTiers.tierId(FamilyTiers.TIER_COUNT - 1 - i);
        (flags, familyId) = policy.flagRules(1 + i);
        require(flags == uint256(1) << expectedId && familyId == expectedId);
      }

      (flags, familyId) = policy.flagRules(1 + FamilyTiers.TIER_COUNT);
      require(flags == uint256(1) << 255 && familyId == NATIVE_MATH_ID);
    }

    {
      uint24[12] memory fees = FamilyTiers.feePips();
      for (uint256 i; i < FamilyTiers.TIER_COUNT; i++) {
        require(policy.familyDefaults(FamilyTiers.tierId(i)) == encodeFee(fees[i]));
      }
    }

    // -----------------------------------------------------------------------------------------
    // Original Deployment Parity Checks
    //
    // The tiered policy must be a strict superset of the live original policy: every fee
    // outcome the original produces today must be reproduced by the tiered policy at the
    // moment the proposal repoints the PoolManager. Compare against live original state,
    // not this script's inputs, so config drift shows up here and not in production.
    //
    // Part-2 chains have no original deployment — the tiered deployment is the first fee
    // infra there, so there is no live state to compare against and the parity section is
    // skipped.
    if (originalRecorder.exists(chainId, "V4FeePolicy")) {
      console.log("Checking parity with original deployment ...");

      V4FeePolicy originalPolicy = V4FeePolicy(originalRecorder.read(chainId, "V4FeePolicy"));

      require(originalPolicy.defaultFee() == policy.defaultFee());
      require(originalPolicy.isHookedNativeMathFeeOn() == policy.isHookedNativeMathFeeOn());

      require(originalPolicy.feeBucketsLength() == policy.feeBucketsLength());
      for (uint256 i; i < feeBuckets.length; i++) {
        (uint24 lpFeeFloor1, uint24 alphaPips1, uint32 betaPips1) = originalPolicy.feeBucket(i);
        (uint24 lpFeeFloor2, uint24 alphaPips2, uint32 betaPips2) = policy.feeBucket(i);
        require(lpFeeFloor1 == lpFeeFloor2 && alphaPips1 == alphaPips2 && betaPips1 == betaPips2);
      }

      {
        (uint256 flags, uint8 familyId) = originalPolicy.flagRules(0);
        require(flags == AGG_HOOK_FAMILY && familyId == AGG_HOOK_ID);
      }

      require(originalPolicy.familyDefaults(AGG_HOOK_ID) == policy.familyDefaults(AGG_HOOK_ID));

      {
        uint256 length = stableStablePairs.chainPairs[chainId].length;
        for (uint256 i; i < length; i++) {
          address token0 = stableStablePairs.chainPairs[chainId][i].token0;
          address token1 = stableStablePairs.chainPairs[chainId][i].token1;

          (token0, token1) = sort(token0, token1);

          bytes32 hash = keccak256(abi.encodePacked(token0, token1));
          require(
            originalPolicy.pairClassFees(hash, AGG_HOOK_ID)
              == policy.pairClassFees(hash, AGG_HOOK_ID)
          );
        }
      }

      {
        HookFamilyAssignment[] memory assignments = hookAssignments(chainId);
        for (uint256 i; i < assignments.length; i++) {
          require(originalPolicy.hookFamilyId(assignments[i].hook) == assignments[i].familyId);
          require(policy.hookFamilyId(assignments[i].hook) == assignments[i].familyId);
        }
      }
    } else {
      console.log("No original deployment recorded for this chain; skipping parity checks.");
    }

    console.log("OK");
    console.log("V4FeeAdapterTiered:", address(adapter));
    console.log("V4FeePolicyTiered:", address(policy));
  }

  /// @dev Hook family assignments per chain, identical to the original prereq. The parity checks
  /// assert these match the live original policy, so any assignment governance expects is here.
  function hookAssignments(uint256 chainId)
    internal
    pure
    returns (HookFamilyAssignment[] memory assignments)
  {
    if (chainId == ChainId.Ethereum) {
      assignments = new HookFamilyAssignment[](5);
      assignments[0] =
        HookFamilyAssignment({hook: 0xd53006d1e3110fD319a79AEEc4c527a0d265E080, familyId: 255}); // aztec
      // (CCA)
      assignments[1] =
        HookFamilyAssignment({hook: 0x890681CfF5AD2069F020027f41f5f68F6a292000, familyId: 255}); // octra
      // (CCA)
      assignments[2] =
        HookFamilyAssignment({hook: 0x358Ac5a3FA0d5A80d78013DBe6A4f290438cA000, familyId: 255}); // strato
      // (CCA)
      assignments[3] =
        HookFamilyAssignment({hook: 0xb98766A35cdc28415be0767D4EA41e39fBA3e000, familyId: 255}); // LBP
      assignments[4] =
        HookFamilyAssignment({hook: 0x49380c4EfaB1b491006aF7FabAB8B3459F0E6000, familyId: 255}); // LBP
    } else if (chainId == ChainId.Base) {
      assignments = new HookFamilyAssignment[](3);
      assignments[0] =
        HookFamilyAssignment({hook: 0xeA9346e83952840E69Beb36Df365C4e68DE0E080, familyId: 255}); // flow
      // (CCA)
      assignments[1] =
        HookFamilyAssignment({hook: 0x5bB4bAfafEc57BEd50D864AAA9D1ef992611e000, familyId: 255}); // LBP
      assignments[2] =
        HookFamilyAssignment({hook: 0x34385dD739FE5464892BF0bA4CC42492804dA000, familyId: 255}); // LBP
    } else if (chainId == Constants.Robinhood.CHAIN_ID) {
      assignments = new HookFamilyAssignment[](3);
      assignments[0] =
        HookFamilyAssignment({hook: 0x05d552391067389EE44fec3924157ed33F976000, familyId: 255}); // LBP
      assignments[1] =
        HookFamilyAssignment({hook: 0xD462a559337859369EF271814851A18F496ba000, familyId: 255}); // quick
      // launch (CCA)
      assignments[2] =
        HookFamilyAssignment({hook: 0x095e38a2135aeBcfFa98A5B6911591937f912000, familyId: 255}); // LBP
    } else if (chainId == ChainId.Arbitrum) {
      assignments = new HookFamilyAssignment[](2);
      assignments[0] =
        HookFamilyAssignment({hook: 0x18608AD558dcD233F7854242bbAef73988Bee000, familyId: 255}); // LBP
      assignments[1] =
        HookFamilyAssignment({hook: 0x8Af0775a70Cc94D71DFc0fE809435e833F2Fe000, familyId: 255}); // LBP
    } else if (chainId == ChainId.XLayer) {
      assignments = new HookFamilyAssignment[](2);
      assignments[0] =
        HookFamilyAssignment({hook: 0x95bcb80e3804a085d23778F2956c305d6488e000, familyId: 255}); // LBP
      assignments[1] =
        HookFamilyAssignment({hook: 0x58DF162fF41e5cB42B8515f75F90C1841938A000, familyId: 255}); // LBP
    }
  }

  /// @dev Resovles the addresses of the pool manager, token jar, and timelock based on chain id.
  function getAddresses(uint256 chainId) internal view returns (address, address, address) {
    if (chainId == ChainId.Ethereum) {
      return (uniswap.ethereum.poolManager, uniswap.ethereum.tokenJar, uniswap.ethereum.timelock);
    }
    if (chainId == ChainId.Arbitrum) {
      return (
        uniswap.arbitrum.poolManager,
        uniswap.arbitrum.tokenJar,
        InboxEncoder.arbitrumAlias(uniswap.ethereum.timelock)
      );
    }
    if (chainId == ChainId.Base) {
      return (uniswap.base.poolManager, uniswap.base.tokenJar, uniswap.base.crossChainAccount);
    }
    if (chainId == ChainId.Celo) {
      return (uniswap.celo.poolManager, uniswap.celo.tokenJar, uniswap.celo.crossChainAccount);
    }
    if (chainId == ChainId.Optimism) {
      return
        (
          uniswap.optimism.poolManager,
          uniswap.optimism.tokenJar,
          uniswap.optimism.crossChainAccount
        );
    }
    if (chainId == ChainId.Soneium) {
      return
        (uniswap.soneium.poolManager, uniswap.soneium.tokenJar, uniswap.soneium.crossChainAccount);
    }
    if (chainId == ChainId.XLayer) {
      return (uniswap.xLayer.poolManager, uniswap.xLayer.tokenJar, uniswap.xLayer.crossChainAccount);
    }
    if (chainId == ChainId.WorldChain) {
      return (
        uniswap.worldChain.poolManager,
        uniswap.worldChain.tokenJar,
        uniswap.worldChain.crossChainAccount
      );
    }
    if (chainId == ChainId.Zora) {
      return (uniswap.zora.poolManager, uniswap.zora.tokenJar, uniswap.zora.crossChainAccount);
    }
    if (chainId == ChainId.BNBChain) {
      return
        (uniswap.bnbChain.poolManager, uniswap.bnbChain.tokenJar, uniswap.bnbChain.wormholeReceiver);
    }
    if (chainId == ChainId.Polygon) {
      return (uniswap.polygon.poolManager, uniswap.polygon.tokenJar, uniswap.polygon.fxReceiver);
    }
    if (chainId == Constants.Robinhood.CHAIN_ID) {
      return (
        Constants.Robinhood.POOL_MANAGER,
        Constants.Robinhood.TOKEN_JAR,
        InboxEncoder.arbitrumAlias(uniswap.ethereum.timelock)
      );
    }

    revert("invalid chain id");
  }

  /// @dev Handles v4 fee two way encoding
  function encodeFee(uint24 fee) internal pure returns (uint24) {
    return fee << 12 | fee;
  }

  /// @dev sort addresses for pool fee assignment.
  function sort(address a, address b) internal pure returns (address, address) {
    return uint160(a) >= uint160(b) ? (b, a) : (a, b);
  }
}
