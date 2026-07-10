// SPDX-License-Identifier: AGPl-3.0-only
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {ChainId} from "govkit/constants/ChainId.sol";

import {V4FeeAdapter} from "../../../src/feeAdapters/V4FeeAdapter.sol";
import {V4FeePolicy} from "../../../src/feeAdapters/V4FeePolicy.sol";
import {FeeBucket, FlagRule, PairClassFeeAssignment} from "../../../src/interfaces/IV4FeePolicy.sol";
import {StableStablePairs} from "../StableStablePairs.sol";

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

        vm.startBroadcast();
        deployAndConfigureV4Infra(ChainId.Ethereum, uniswap.ethereum.poolManager, uniswap.ethereum.tokenJar);
        vm.stopBroadcast();
        // Ethereum, Arbitrum, Base, Celo, OP Mainnet, Soneium, X Layer, Worldchain, Zora, BNB Chain, and Polygon
    }

    function deployAndConfigureV4Infra(
        uint256 chainId,
        address poolManager,
        address tokenJar
    ) internal {
        address scriptRunnerEoa = msg.sender;

        // -----------------------------------------------------------------------------------------
        // Deploy V4FeeAdapter
        //
        V4FeeAdapter adapter;
        if (!recorder.exists(chainId, "V4FeeAdapter")) {
            adapter = new V4FeeAdapter({
                poolManager: IPoolManager(poolManager),
                tokenJar: tokenJar
            });

            recorder.write({
                chainId: chainId,
                deploymentName: "V4FeeAdapter",
                deployment: address(adapter)
            });
        } else {
            adapter = V4FeeAdapter(recorder.read(chainId, "V4FeeAdapter"));
        }

        // -----------------------------------------------------------------------------------------
        // Deploy V4FeePolicy
        //
        V4FeePolicy policy;
        if (!recorder.exists(chainId, "V4FeePolicy")) {
            policy = new V4FeePolicy({
                poolManager: IPoolManager(poolManager)
            });

            recorder.write({
                chainId: chainId,
                deploymentName: "V4FeePolicy",
                deployment: address(policy)
            });
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
        {
        FeeBucket[] memory feeBuckets = new FeeBucket[](8);
        feeBuckets[0] = FeeBucket({lpFeeFloor: 0, alphaPips: 1, betaPips: 0});
        feeBuckets[1] = FeeBucket({
            lpFeeFloor: 3,
            alphaPips: 1,
            betaPips: 263889
        });
        feeBuckets[2] = FeeBucket({
            lpFeeFloor: 75,
            alphaPips: 20,
            betaPips: 200000
        });
        feeBuckets[3] = FeeBucket({
            lpFeeFloor: 100,
            alphaPips: 25,
            betaPips: 272727
        });
        feeBuckets[4] = FeeBucket({
            lpFeeFloor: 375,
            alphaPips: 100,
            betaPips: 200000
        });
        feeBuckets[5] = FeeBucket({
            lpFeeFloor: 500,
            alphaPips: 125,
            betaPips: 137500
        });
        feeBuckets[6] = FeeBucket({
            lpFeeFloor: 2500,
            alphaPips: 400,
            betaPips: 200000
        });
        feeBuckets[7] = FeeBucket({
            lpFeeFloor: 5500,
            alphaPips: 1000,
            betaPips: 0
        });
        policy.setFeeBuckets(feeBuckets);
        }

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
        flagRules[0] = FlagRule({
            requiredFlags: AGG_HOOK_FAMILY,
            familyId: AGG_HOOK_ID
        });
        flagRules[1] = FlagRule({
            requiredFlags: PARITY_HOOK_FAMILY,
            familyId: PARITY_HOOK_ID
        });
        policy.setFlagRules(flagRules);
        }

        // -----------------------------------------------------------------------------------------
        // Set Aggregator Hook Fees
        //
        {
        uint24 defaultFeeValue = chainId == ChainId.Base ? 300 : 1_000;
        uint24 stableStableFeeValue = chainId == ChainId.Base ? 100 : 300;

        policy.setFamilyDefault({
            familyId: AGG_HOOK_ID,
            feeValue: defaultFeeValue
        });

        uint256 length = stableStablePairs.chainPairs[chainId].length;

        PairClassFeeAssignment[]
            memory assignments = new PairClassFeeAssignment[](length);
        for (uint256 i; i < length; i++) {
            address token0 = stableStablePairs.chainPairs[chainId][i].token0;
            address token1 = stableStablePairs.chainPairs[chainId][i].token1;

            (token0, token1) = uint160(token0) >= uint160(token1)
                ? (token1, token0)
                : (token0, token1);

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
        policy.setFamilyDefault({
            familyId: PARITY_HOOK_ID,
            feeValue: 0
        });
    }
}
