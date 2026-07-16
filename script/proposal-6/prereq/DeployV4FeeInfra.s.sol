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
  PairClassFeeAssignment,
  HookFamilyAssignment
} from "../../../src/interfaces/IV4FeePolicy.sol";
import {StableStablePairs} from "../StableStablePairs.sol";

import "../Constants.sol" as Constants;

uint256 constant AGG_HOOK_FAMILY = 1 << 11;
uint8 constant AGG_HOOK_ID = 11;
uint256 constant PARITY_HOOK_FAMILY = 1 << 12;
uint8 constant PARITY_HOOK_ID = 12;

contract DeployV4FeeInfra is Script {
  Recorder internal recorder;
  Uniswap internal uniswap;
  StableStablePairs internal stableStablePairs;

  function run() external {
    uniswap.loadLatest();
    recorder.initialize("DeployV4FeeInfra");
    stableStablePairs.initialize();

    address scriptRunnerEoa = msg.sender;
    uint256 chainId = block.chainid;

    (address poolManager, address tokenJar, address postConfigOwner) = getAddresses(chainId);

    vm.startBroadcast();

    // -----------------------------------------------------------------------------------------
    // Deploy V4FeeAdapter
    //
    V4FeeAdapter adapter;
    if (!recorder.exists(chainId, "V4FeeAdapter")) {
      adapter = new V4FeeAdapter({poolManager: IPoolManager(poolManager), tokenJar: tokenJar});

      recorder.write({
        chainId: chainId, deploymentName: "V4FeeAdapter", deployment: address(adapter)
      });
    } else {
      adapter = V4FeeAdapter(recorder.read(chainId, "V4FeeAdapter"));
    }

    // -----------------------------------------------------------------------------------------
    // Deploy V4FeePolicy
    //
    V4FeePolicy policy;
    if (!recorder.exists(chainId, "V4FeePolicy")) {
      policy = new V4FeePolicy({poolManager: IPoolManager(poolManager)});

      recorder.write({chainId: chainId, deploymentName: "V4FeePolicy", deployment: address(policy)});
    } else {
      policy = V4FeePolicy(recorder.read(chainId, "V4FeePolicy"));
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
    // Assign Fee Buckets
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
    // Set Flag Rules
    //
    // | Name             | ID   | Flags     |
    // | ---------------- | ---- | --------- |
    // | Aggregator Hooks | `11` | `1 << 11` |
    // | Parity Hooks     | `12` | `1 << 12` |
    //
    {
      FlagRule[] memory flagRules = new FlagRule[](2);
      flagRules[0] = FlagRule({requiredFlags: AGG_HOOK_FAMILY, familyId: AGG_HOOK_ID});
      flagRules[1] = FlagRule({requiredFlags: PARITY_HOOK_FAMILY, familyId: PARITY_HOOK_ID});
      policy.setFlagRules(flagRules);
    }

    // -----------------------------------------------------------------------------------------
    // Set Aggregator Hook Fees
    //
    {
      uint24 defaultFeeValue = chainId == ChainId.Base ? 300 : 1000;
      uint24 stableStableFeeValue = chainId == ChainId.Base ? 100 : 300;

      policy.setFamilyDefault({familyId: AGG_HOOK_ID, feeValue: defaultFeeValue});

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
          feeValue: stableStableFeeValue
        });
      }
      policy.batchSetPairClassFee(assignments);
    }

    // -----------------------------------------------------------------------------------------
    // Set Parity Hook Fees
    //
    policy.setFamilyDefault({familyId: PARITY_HOOK_ID, feeValue: 0});

    // -----------------------------------------------------------------------------------------
    // Set LBP & CCA Hooks
    //
    if (chainId == ChainId.Ethereum) {
      HookFamilyAssignment[] memory assignments = new HookFamilyAssignment[](5);
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
      policy.batchSetHookFamily(assignments);
    }

    if (chainId == ChainId.Base) {
      HookFamilyAssignment[] memory assignments = new HookFamilyAssignment[](3);
      assignments[0] =
        HookFamilyAssignment({hook: 0xeA9346e83952840E69Beb36Df365C4e68DE0E080, familyId: 255}); // flow
      // (CCA)
      assignments[1] =
        HookFamilyAssignment({hook: 0x5bB4bAfafEc57BEd50D864AAA9D1ef992611e000, familyId: 255}); // LBP
      assignments[2] =
        HookFamilyAssignment({hook: 0x34385dD739FE5464892BF0bA4CC42492804dA000, familyId: 255}); // LBP
      policy.batchSetHookFamily(assignments);
    }

    if (chainId == Constants.Robinhood.CHAIN_ID) {
      HookFamilyAssignment[] memory assignments = new HookFamilyAssignment[](2);
      assignments[0] =
        HookFamilyAssignment({hook: 0x05d552391067389EE44fec3924157ed33F976000, familyId: 255}); // LBP
      assignments[1] =
        HookFamilyAssignment({hook: 0xD462a559337859369EF271814851A18F496ba000, familyId: 255}); // new
      // hook
      policy.batchSetHookFamily(assignments);
    }

    if (chainId == ChainId.UniChain) {
      HookFamilyAssignment[] memory assignments = new HookFamilyAssignment[](2);
      assignments[0] =
        HookFamilyAssignment({hook: 0x824A3eCDe463DD45cC156b64CEfA132596C9A000, familyId: 255}); // LBP
      assignments[1] =
        HookFamilyAssignment({hook: 0x298eA05D0356B2Ae5cCAa3169E471783ee9EA000, familyId: 255}); // LBP
    }
    if (chainId == ChainId.Arbitrum) {
      HookFamilyAssignment[] memory assignments = new HookFamilyAssignment[](2);
      assignments[0] =
        HookFamilyAssignment({hook: 0x18608AD558dcD233F7854242bbAef73988Bee000, familyId: 255}); // LBP
      assignments[1] =
        HookFamilyAssignment({hook: 0x8Af0775a70Cc94D71DFc0fE809435e833F2Fe000, familyId: 255}); // LBP
    }
    if (chainId == ChainId.XLayer) {
      HookFamilyAssignment[] memory assignments = new HookFamilyAssignment[](2);
      assignments[0] =
        HookFamilyAssignment({hook: 0x95bcb80e3804a085d23778F2956c305d6488e000, familyId: 255}); // LBP
      assignments[1] =
        HookFamilyAssignment({hook: 0x58DF162fF41e5cB42B8515f75F90C1841938A000, familyId: 255}); // LBP
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
    require(policy.feeBucketsLength() == feeBuckets.length);

    for (uint256 i; i < feeBuckets.length; i++) {
      (uint24 lpFeeFloor, uint24 alphaPips, uint32 betaPips) = policy.feeBucket(i);
      require(lpFeeFloor == feeBuckets[i].lpFeeFloor);
      require(alphaPips == feeBuckets[i].alphaPips);
      require(betaPips == feeBuckets[i].betaPips);
    }

    require(policy.flagRulesLength() == 2);
    {
      (uint256 hookFamily, uint8 hookId) = policy.flagRules(0);
      require(hookFamily == AGG_HOOK_FAMILY);
      require(hookId == AGG_HOOK_ID);
    }
    {
      (uint256 hookFamily, uint8 hookId) = policy.flagRules(1);
      require(hookFamily == PARITY_HOOK_FAMILY);
      require(hookId == PARITY_HOOK_ID);
    }

    if (chainId == ChainId.Base) require(policy.familyDefaults(AGG_HOOK_ID) == 300);
    else require(policy.familyDefaults(AGG_HOOK_ID) == 1000);

    uint256 len = stableStablePairs.chainPairs[chainId].length;

    for (uint256 i; i < len; i++) {
      address token0 = stableStablePairs.chainPairs[chainId][i].token0;
      address token1 = stableStablePairs.chainPairs[chainId][i].token1;

      (token0, token1) = sort(token0, token1);

      bytes32 hash = keccak256(abi.encodePacked(token0, token1));

      if (chainId == ChainId.Base) require(policy.pairClassFees(hash, AGG_HOOK_ID) == 100);
      else require(policy.pairClassFees(hash, AGG_HOOK_ID) == 300);
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

  /// @dev sort addresses for pool fee assignment.
  function sort(address a, address b) internal pure returns (address, address) {
    return uint160(a) >= uint160(b) ? (b, a) : (a, b);
  }
}
