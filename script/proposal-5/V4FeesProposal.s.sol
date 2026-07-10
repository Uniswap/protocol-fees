// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";

import {Uniswap} from "lib/govkit/src/types/Uniswap.sol";
import {Proposal} from "lib/govkit/src/types/Proposal.sol";
import {ChainId} from "lib/govkit/src/constants/ChainId.sol";
import {Call, LibCall} from "lib/govkit/src/types/Call.sol";
import {GovernanceSeatbelt} from "lib/govkit/src/forge/GovernanceSeatbelt.sol";
import {FxRootEncoder} from "lib/govkit/src/bridges/FxRootEncoder.sol";
import {InboxEncoder} from "lib/govkit/src/bridges/InboxEncoder.sol";
import {L1CrossDomainMessengerEncoder} from "lib/govkit/src/bridges/L1CrossDomainMessengerEncoder.sol";
import {OptimismPortal2Encoder} from "lib/govkit/src/bridges/OptimismPortal2Encoder.sol";
import {WormholeEncoder} from "lib/govkit/src/bridges/WormholeEncoder.sol";
import {IPoolManager} from "lib/govkit/src/interfaces/IPoolManager.sol";

import {V4FeeController} from "./Constants.sol";

string constant DESCRIPTION = "TODO";

contract V4FeeActivationProposal is Script {
    Uniswap internal uniswap;

    function run() public {
        vm.createDir("./out/.seatbelt/", true);

        Call memory PLACEHOLDER = Call(address(0), 0, new bytes(0));

        uniswap.loadLatest();
        {
            // ---------------------------------------------------------------------------------------------
            // 00: Activate V4 Fees for Ethereum.
            //
            Call memory activateV4FeesEthereum = Call({
                target: uniswap.ethereum.poolManager,
                value: 0,
                data: abi.encodeCall(
                    IPoolManager.setProtocolFeeController,
                    (V4FeeController.Ethereum)
                )
            });

            // ---------------------------------------------------------------------------------------------
            // 01: Activate V4 Fees for Arbitrum.
            //
            Call memory activateV4FeesArbitrum = InboxEncoder.encode({
                inbox: uniswap.ethereum.bridge.arbitrum,
                timelock: uniswap.ethereum.timelock,
                remoteCall: Call({
                    target: uniswap.arbitrum.poolManager,
                    value: 0,
                    data: abi.encodeCall(
                        IPoolManager.setProtocolFeeController,
                        (V4FeeController.Arbitrum)
                    )
                })
            });

            // ---------------------------------------------------------------------------------------------
            // 02: Activate V4 Fees for Base.
            //
            Call memory activateV4FeesBase = L1CrossDomainMessengerEncoder
                .encode({
                    l1CrossDomainMessenger: uniswap.ethereum.bridge.base,
                    crossChainAccount: uniswap.base.crossChainAccount,
                    remoteCall: Call({
                        target: uniswap.base.poolManager,
                        value: 0,
                        data: abi.encodeCall(
                            IPoolManager.setProtocolFeeController,
                            (V4FeeController.Base)
                        )
                    })
                });

            // ---------------------------------------------------------------------------------------------
            // 03: Activate V4 Fees for BNB Chain.
            //
            Call memory activateV4FeesBNBChain = WormholeEncoder.encode({
                sourceSender: uniswap.ethereum.bridge.bnbChain,
                remoteReceiver: uniswap.bnbChain.wormholeReceiver,
                chainId: ChainId.BNBChain,
                value: 0,
                remoteCalls: LibCall.newCalls(
                    [
                        Call({
                            target: uniswap.bnbChain.poolManager,
                            value: 0,
                            data: abi.encodeCall(
                                IPoolManager.setProtocolFeeController,
                                (V4FeeController.BNBChain)
                            )
                        })
                    ]
                )
            });

            // ---------------------------------------------------------------------------------------------
            // 04: Activate V4 Fees for Celo.
            //
            Call memory activateV4FeesCelo = L1CrossDomainMessengerEncoder
                .encode({
                    l1CrossDomainMessenger: uniswap.ethereum.bridge.celo,
                    crossChainAccount: uniswap.celo.crossChainAccount,
                    remoteCall: Call({
                        target: uniswap.celo.poolManager,
                        value: 0,
                        data: abi.encodeCall(
                            IPoolManager.setProtocolFeeController,
                            (V4FeeController.Celo)
                        )
                    })
                });

            // ---------------------------------------------------------------------------------------------
            // 05: Activate V4 Fees for OP Mainnet
            //
            Call memory activateV4FeesOPMainnet = L1CrossDomainMessengerEncoder
                .encode({
                    l1CrossDomainMessenger: uniswap.ethereum.bridge.optimism,
                    crossChainAccount: uniswap.optimism.crossChainAccount,
                    remoteCall: Call({
                        target: uniswap.optimism.poolManager,
                        value: 0,
                        data: abi.encodeCall(
                            IPoolManager.setProtocolFeeController,
                            (V4FeeController.Optimism)
                        )
                    })
                });

            Proposal memory v4FeeActivationProposalPartOne = Proposal({
                description: string.concat("Part 1/2:\n", DESCRIPTION),
                calls: LibCall.newCalls(
                    [
                        activateV4FeesEthereum,
                        activateV4FeesArbitrum,
                        activateV4FeesBase,
                        activateV4FeesBNBChain,
                        activateV4FeesCelo,
                        activateV4FeesOPMainnet
                    ]
                )
            });

            vm.writeFile({
                path: "./out/.seatbelt/V4FeeActivationProposalPartOne.json",
                data: GovernanceSeatbelt.toJson({
                    proposal: v4FeeActivationProposalPartOne,
                    governorBravo: uniswap.ethereum.governorBravo
                })
            });
        }
        {
            // ---------------------------------------------------------------------------------------------
            // 06: Activate V4 Fees for Polygon.
            //
            Call memory activateV4FeesPolygon = FxRootEncoder.encode({
                fxRoot: uniswap.ethereum.bridge.polygon,
                fxReceiver: uniswap.polygon.fxReceiver,
                remoteCalls: LibCall.newCalls(
                    [
                        Call({
                            target: uniswap.polygon.poolManager,
                            value: 0,
                            data: abi.encodeCall(
                                IPoolManager.setProtocolFeeController,
                                (V4FeeController.Polygon)
                            )
                        })
                    ]
                )
            });

            // ---------------------------------------------------------------------------------------------
            // 07: Activate V4 Fees for Soneium.
            //
            Call memory activateV4FeesSoneium = PLACEHOLDER;

            // ---------------------------------------------------------------------------------------------
            // 08: Activate V4 Fees for Worldchain.
            //
            Call memory activateV4FeesWorldchain = OptimismPortal2Encoder
                .encode({
                    portal: uniswap.ethereum.bridge.worldChain,
                    remoteCall: Call({
                        target: uniswap.worldChain.poolManager,
                        value: 0,
                        data: abi.encodeCall(
                            IPoolManager.setProtocolFeeController,
                            (V4FeeController.WorldChain)
                        )
                    })
                });

            // ---------------------------------------------------------------------------------------------
            // 09: Activate V4 Fees for X Layer
            //
            Call memory activateV4FeesXLayer = PLACEHOLDER;

            // ---------------------------------------------------------------------------------------------
            // 10: Activate V4 Fees for Zora.
            //
            Call memory activateV4FeesZora = PLACEHOLDER;

            Proposal memory v4FeeActivationProposalPartTwo = Proposal({
                description: string.concat("Part 2/2:\n", DESCRIPTION),
                calls: LibCall.newCalls(
                    [
                        activateV4FeesPolygon,
                        activateV4FeesSoneium,
                        activateV4FeesWorldchain,
                        activateV4FeesXLayer,
                        activateV4FeesZora
                    ]
                )
            });

            vm.writeFile({
                path: "./out/.seatbelt/V4FeeActivationProposalPartTwo.json",
                data: GovernanceSeatbelt.toJson({
                    proposal: v4FeeActivationProposalPartTwo,
                    governorBravo: uniswap.ethereum.governorBravo
                })
            });
        }
    }
}
