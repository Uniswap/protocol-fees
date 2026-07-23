// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";

import {Recorder} from "govkit/forge/Recorder.sol";
import {Uniswap} from "govkit/types/Uniswap.sol";
import {Proposal} from "govkit/types/Proposal.sol";
import {ChainId} from "govkit/constants/ChainId.sol";
import {Call, LibCall} from "govkit/types/Call.sol";
import {GovernanceSeatbelt} from "govkit/forge/GovernanceSeatbelt.sol";
import {FxRootEncoder} from "govkit/bridges/FxRootEncoder.sol";
import {InboxEncoder} from "govkit/bridges/InboxEncoder.sol";
import {L1CrossDomainMessengerEncoder} from "govkit/bridges/L1CrossDomainMessengerEncoder.sol";
import {WormholeEncoder} from "govkit/bridges/WormholeEncoder.sol";
import {IPoolManager} from "govkit/interfaces/IPoolManager.sol";

import "../proposal-5/Constants.sol" as Constants;

import {PART_TWO_DESCRIPTION, FAMILY_UPGRADE_DESCRIPTION} from "./Description.sol";

enum Prop {
  /// @dev The 2nd v4 fee proposal: activates v4 fees on the part-2 chains by registering
  /// the tiered adapter (tier families + native-math opt-in included) as protocolFeeController.
  PartTwoActivation,
  /// @dev Upgrades the part-1 chains (live since the 1st v4 fee proposal) to the tiered adapter,
  /// activating the tier families and native-math opt-in there.
  PartOneUpgrade
}

/// @dev Toggle this to build the part-2 activation or the part-1 upgrade proposal.
Prop constant V4_FEES_UPGRADE_PROP = Prop.PartTwoActivation;

/// @notice Both proposals are a single action shape: point each chain's PoolManager at the
/// fully-configured tiered fee adapter deployed by DeployTieredV4FeeInfra. The tiered
/// adapter arrives wired (policy set, authority with governance), so no configuration
/// calls cross a bridge. On part-1 chains the swap is atomic — the original adapter serves
/// fees until the action executes, and fees already pushed to PoolManagers are identical
/// under the tiered policy (parity is asserted onchain by the prereq), so no retrigger is
/// required.
contract V4FeesUpgradeProposal is Script {
  Recorder internal recorder;
  Uniswap internal uniswap;

  function run() public {
    vm.createDir("./out/.seatbelt/", true);
    recorder.initialize("DeployTieredV4FeeInfra");
    uniswap.loadLatest();

    if (V4_FEES_UPGRADE_PROP == Prop.PartTwoActivation) {
      require(keccak256(bytes(PART_TWO_DESCRIPTION)) != keccak256(bytes("TODO")));

      // ---------------------------------------------------------------------------------------------
      // 00: Activate V4 Fees for Celo.
      //
      Call memory activateV4FeesCelo = L1CrossDomainMessengerEncoder.encode({
        l1CrossDomainMessenger: uniswap.ethereum.bridge.celo,
        crossChainAccount: uniswap.celo.crossChainAccount,
        remoteCall: Call({
          target: uniswap.celo.poolManager,
          value: 0,
          data: abi.encodeCall(
            IPoolManager.setProtocolFeeController,
            (recorder.read(ChainId.Celo, "V4FeeAdapterTiered"))
          )
        })
      });

      // ---------------------------------------------------------------------------------------------
      // 01: Activate V4 Fees for Soneium.
      //
      Call memory activateV4FeesSoneium = L1CrossDomainMessengerEncoder.encode({
        l1CrossDomainMessenger: uniswap.ethereum.bridge.soneium,
        crossChainAccount: uniswap.soneium.crossChainAccount,
        remoteCall: Call({
          target: uniswap.soneium.poolManager,
          value: 0,
          data: abi.encodeCall(
            IPoolManager.setProtocolFeeController,
            (recorder.read(ChainId.Soneium, "V4FeeAdapterTiered"))
          )
        })
      });

      // ---------------------------------------------------------------------------------------------
      // 02: Activate V4 Fees for Worldchain.
      //
      Call memory activateV4FeesWorldchain = L1CrossDomainMessengerEncoder.encode({
        l1CrossDomainMessenger: uniswap.ethereum.bridge.worldChain,
        crossChainAccount: uniswap.worldChain.crossChainAccount,
        remoteCall: Call({
          target: uniswap.worldChain.poolManager,
          value: 0,
          data: abi.encodeCall(
            IPoolManager.setProtocolFeeController,
            (recorder.read(ChainId.WorldChain, "V4FeeAdapterTiered"))
          )
        })
      });

      // ---------------------------------------------------------------------------------------------
      // 03: Activate V4 Fees for X Layer.
      //
      Call memory activateV4FeesXLayer = L1CrossDomainMessengerEncoder.encode({
        l1CrossDomainMessenger: uniswap.ethereum.bridge.xLayer,
        crossChainAccount: uniswap.xLayer.crossChainAccount,
        remoteCall: Call({
          target: uniswap.xLayer.poolManager,
          value: 0,
          data: abi.encodeCall(
            IPoolManager.setProtocolFeeController,
            (recorder.read(ChainId.XLayer, "V4FeeAdapterTiered"))
          )
        })
      });

      // ---------------------------------------------------------------------------------------------
      // 04: Activate V4 Fees for Zora.
      //
      Call memory activateV4FeesZora = L1CrossDomainMessengerEncoder.encode({
        l1CrossDomainMessenger: uniswap.ethereum.bridge.zora,
        crossChainAccount: uniswap.zora.crossChainAccount,
        remoteCall: Call({
          target: uniswap.zora.poolManager,
          value: 0,
          data: abi.encodeCall(
            IPoolManager.setProtocolFeeController,
            (recorder.read(ChainId.Zora, "V4FeeAdapterTiered"))
          )
        })
      });

      Proposal memory partTwoActivation = Proposal({
        description: string.concat(
          "# Activate v4 Protocol Fees (Part 2/2) \n\n", PART_TWO_DESCRIPTION
        ),
        calls: LibCall.newCalls(
          [
            activateV4FeesCelo,
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
          proposal: partTwoActivation, governorBravo: uniswap.ethereum.governorBravo
        })
      });
    }

    if (V4_FEES_UPGRADE_PROP == Prop.PartOneUpgrade) {
      require(keccak256(bytes(FAMILY_UPGRADE_DESCRIPTION)) != keccak256(bytes("TODO")));
      require(Constants.Robinhood.TOKEN_JAR != address(0x00));

      // ---------------------------------------------------------------------------------------------
      // 00: Upgrade V4 Fee Adapter for Ethereum.
      //
      Call memory upgradeV4FeesEthereum = Call({
        target: uniswap.ethereum.poolManager,
        value: 0,
        data: abi.encodeCall(
          IPoolManager.setProtocolFeeController,
          (recorder.read(ChainId.Ethereum, "V4FeeAdapterTiered"))
        )
      });

      // ---------------------------------------------------------------------------------------------
      // 01: Upgrade V4 Fee Adapter for Arbitrum.
      //
      Call memory upgradeV4FeesArbitrum = InboxEncoder.encode({
        inbox: uniswap.ethereum.bridge.arbitrum,
        timelock: uniswap.ethereum.timelock,
        remoteCall: Call({
          target: uniswap.arbitrum.poolManager,
          value: 0,
          data: abi.encodeCall(
            IPoolManager.setProtocolFeeController,
            (recorder.read(ChainId.Arbitrum, "V4FeeAdapterTiered"))
          )
        })
      });

      // ---------------------------------------------------------------------------------------------
      // 02: Upgrade V4 Fee Adapter for Base.
      //
      Call memory upgradeV4FeesBase = L1CrossDomainMessengerEncoder.encode({
        l1CrossDomainMessenger: uniswap.ethereum.bridge.base,
        crossChainAccount: uniswap.base.crossChainAccount,
        remoteCall: Call({
          target: uniswap.base.poolManager,
          value: 0,
          data: abi.encodeCall(
            IPoolManager.setProtocolFeeController,
            (recorder.read(ChainId.Base, "V4FeeAdapterTiered"))
          )
        })
      });

      // ---------------------------------------------------------------------------------------------
      // 03: Upgrade V4 Fee Adapter for BNB Chain.
      //
      Call memory upgradeV4FeesBNBChain = WormholeEncoder.encode({
        sourceSender: uniswap.ethereum.bridge.bnbChain,
        remoteReceiver: uniswap.bnbChain.wormholeReceiver,
        chainId: ChainId.BNBChain,
        value: 0,
        remoteCalls: LibCall.newCalls(
          [Call({
              target: uniswap.bnbChain.poolManager,
              value: 0,
              data: abi.encodeCall(
                IPoolManager.setProtocolFeeController,
                (recorder.read(ChainId.BNBChain, "V4FeeAdapterTiered"))
              )
            })]
        )
      });

      // ---------------------------------------------------------------------------------------------
      // 04: Upgrade V4 Fee Adapter for Polygon.
      //
      Call memory upgradeV4FeesPolygon = FxRootEncoder.encode({
        fxRoot: uniswap.ethereum.bridge.polygon,
        fxReceiver: uniswap.polygon.fxReceiver,
        remoteCalls: LibCall.newCalls(
          [Call({
              target: uniswap.polygon.poolManager,
              value: 0,
              data: abi.encodeCall(
                IPoolManager.setProtocolFeeController,
                (recorder.read(ChainId.Polygon, "V4FeeAdapterTiered"))
              )
            })]
        )
      });

      // ---------------------------------------------------------------------------------------------
      // 05: Upgrade V4 Fee Adapter for Optimism.
      //
      Call memory upgradeV4FeesOPMainnet = L1CrossDomainMessengerEncoder.encode({
        l1CrossDomainMessenger: uniswap.ethereum.bridge.optimism,
        crossChainAccount: uniswap.optimism.crossChainAccount,
        remoteCall: Call({
          target: uniswap.optimism.poolManager,
          value: 0,
          data: abi.encodeCall(
            IPoolManager.setProtocolFeeController,
            (recorder.read(ChainId.Optimism, "V4FeeAdapterTiered"))
          )
        })
      });

      // ---------------------------------------------------------------------------------------------
      // 06: Upgrade V4 Fee Adapter for Robinhood.
      //
      Call memory upgradeV4FeesRobinhood = InboxEncoder.encode({
        inbox: Constants.Ethereum.RH_INBOX,
        timelock: uniswap.ethereum.timelock,
        remoteCall: Call({
          target: Constants.Robinhood.POOL_MANAGER,
          value: 0,
          data: abi.encodeCall(
            IPoolManager.setProtocolFeeController,
            (recorder.read(Constants.Robinhood.CHAIN_ID, "V4FeeAdapterTiered"))
          )
        })
      });

      Proposal memory partOneUpgrade = Proposal({
        description: string.concat(
          "# Activate v4 Hook Fee Families (Part 1 Chains) \n\n", FAMILY_UPGRADE_DESCRIPTION
        ),
        calls: LibCall.newCalls(
          [
            upgradeV4FeesEthereum,
            upgradeV4FeesArbitrum,
            upgradeV4FeesBase,
            upgradeV4FeesBNBChain,
            upgradeV4FeesPolygon,
            upgradeV4FeesOPMainnet,
            upgradeV4FeesRobinhood
          ]
        )
      });

      vm.writeFile({
        path: "./out/.seatbelt/V4FeeFamilyUpgradePartOne.json",
        data: GovernanceSeatbelt.toJson({
          proposal: partOneUpgrade, governorBravo: uniswap.ethereum.governorBravo
        })
      });
    }
  }
}
