# Proposal 7

Activates v2, v3, and v4 protocol fees on HyperEVM, and registers HyperEVM as a Wormhole NTT peer on Ethereum so that UNI burned there releases on mainnet.

HyperEVM has no canonical bridge to Ethereum, so the burn path uses Wormhole's Native Token Transfer system, the same mechanism proposal 4 activated for BNB Chain and Polygon. Fee infrastructure is deployed permissionlessly ahead of the vote and handed to the governance-owned Wormhole receiver, so the proposal itself only does the two things governance alone can do: register the peer on Ethereum, and flip the three fee switches on HyperEVM over Wormhole.

## Wormhole context

Unchanged from proposal 4. See its [Wormhole Context](../proposal-4/Index.md#wormhole-context) for the send and receive paths, the burn-over-Wormhole flow, and the note on why the NTT contracts use ERC-1967 proxies.

## HyperEVM context

HyperEVM produces two kinds of blocks. Small blocks land every second with a 3M gas limit; big blocks land once a minute with a 30M limit. Which kind a transaction lands in is a flag on the sender's HyperCore account, not a property of the transaction.

Deploying the `NttManager` implementation alone costs about 4.5M gas, which no small block can hold. Before running either prerequisite script the deployer must opt in:

```json
{"type": "evmUserModify", "usingBigBlocks": true}
```

Every transaction from that account then waits on the one-minute cadence until the flag is unset, which should happen only after both prerequisite scripts have run.

Both scripts also need a HYPE balance for gas **and** for Wormhole core message fees. The fee is zero on HyperEVM today, matching BNB Chain, but should be queried at run time.

| Name                | Network  | Value                                        | Description                                     |
| ------------------- | -------- | -------------------------------------------- | ----------------------------------------------- |
| `CHAIN_ID`          | HyperEVM | `999`                                        | EIP-155 chain id                                |
| `WORMHOLE_CHAIN_ID` | HyperEVM | `47`                                         | Wormhole-defined chain id                       |
| `WORMHOLE_CORE`     | HyperEVM | `0x7C0faFc4384551f063e05aee704ab943b8B53aB3` | Wormhole core bridge, deployed by Wormhole      |
| `WORMHOLE_SENDER`   | Ethereum | `0xf5F4496219F31CDCBa6130B5402873624585615a` | Uniswap's Wormhole sender, owned by the Timelock |

New-chain addresses live in [`Constants.sol`](./Constants.sol) until the proposal activating them has executed, then move to govkit's address book. That file is the single source for every value below; the tables in this document restate it, so change it first.

## Prerequisite actions

These are permissionless and must all be done before governance can act. Steps 1 and 2 share one record file, `.records/HyperEVM.json`, which step 3 reads. Steps 1 and 2 each refuse to run twice; clear the record deliberately to redeploy.

1. [Deploy Wormhole infra](#1-deploy-wormhole-infra)
2. [Deploy and configure fee infra](#2-deploy-and-configure-fee-infra)
3. [Write the proposal](#3-write-the-proposal)

### 1. Deploy Wormhole infra

**Overview**:

On HyperEVM we deploy `SyntheticNttUni`, `NttManagerNoRateLimiting`, `WormholeTransceiver`, and `ERC1967Proxy` contracts for the latter. We initialize the proxies, register the transceiver with the manager, set `SyntheticNttUni`'s minting authority to the manager, and register Ethereum as a peer on both. We then transfer everything to the governance receiver and renounce the pauser capability on both proxies.

Proposal 4 split this into deploy and configure scripts per chain, because the infra for Ethereum was brought up in the same proposal and so the peers were not known until every chain had deployed. Nothing is deployed on the Ethereum side this time, so the peers are known up front and the two halves collapse into one run.

**Foundry Script**:

[`./prereq/DeployWormholeInfraHyperEVM.s.sol`](./prereq/DeployWormholeInfraHyperEVM.s.sol)

**Shell Command**:

```bash
# from root directory of this repository:
forge script script/proposal-7/prereq/DeployWormholeInfraHyperEVM.s.sol --rpc-url hyperevm --broadcast
```

**Transactions**:

| Index | Action                                                                              |
| ----- | ----------------------------------------------------------------------------------- |
| 00    | (Implicit) Deploy the `TransceiverStructs` external library for wormhole contracts. |
| 01    | Deploy `SyntheticNttUni`.                                                           |
| 02    | Deploy `NttManager` implementation.                                                 |
| 03    | Deploy `NttManager` proxy.                                                          |
| 04    | Initialize `NttManager` proxy.                                                      |
| 05    | Deploy `WormholeTransceiver` implementation.                                        |
| 06    | Deploy `WormholeTransceiver` proxy.                                                 |
| 07    | Initialize `WormholeTransceiver` proxy.                                             |
| 08    | Set `NttManager` proxy's transceiver to the `WormholeTransceiver` proxy.            |
| 09    | Set `SyntheticNttUni` mint authority to `NttManager` proxy.                         |
| 10    | Set the Ethereum `WormholeTransceiver` as a peer.                                   |
| 11    | Set the Ethereum `NttManager` as a peer.                                            |
| 12    | Transfer ownership of `SyntheticNttUni` to governance.                              |
| 13    | Transfer ownership of `NttManager`, and with it the transceiver, to governance.     |
| 14    | Renounce pauser capability on the `WormholeTransceiver` proxy.                      |
| 15    | Renounce pauser capability on the `NttManager` proxy.                               |

> Note: proposal 4 and Wormhole's own script call `setThreshold(1)` after registering the transceiver. It is a no-op, because registering the first transceiver already raises the threshold from 0 to 1 and the manager rejects any value above the number of enabled transceivers. Here, we omit the transaction and assert the property instead.

**Verification**:

Re-runs every assertion against the chain rather than against the simulation, reading the deployment out of the record:

```bash
forge script script/proposal-7/prereq/DeployWormholeInfraHyperEVM.s.sol --sig "check()" --rpc-url hyperevm
```

### 2. Deploy and configure fee infra

**Overview**:

On HyperEVM we deploy `TokenJar`, `WormholeReleaser`, `V3OpenFeeAdapter`, `V4FeeAdapter`, and `V4FeePolicy`, reading the NTT manager and synthetic UNI back out of step 1's record. Each contract keeps deployer authority only for as long as its own configuration needs, then hands both ownership and the fee-setter role to the governance receiver.

The v3 tier defaults match every chain where fees are live. The v4 fee buckets, aggregator flag rule, and aggregator family default match every chain configured by proposal 6.

**Foundry Script**:

[`./prereq/DeployAndConfigureFeeInfraHyperEVM.s.sol`](./prereq/DeployAndConfigureFeeInfraHyperEVM.s.sol)

**Shell Command**:

```bash
# from root directory of this repository:
forge script script/proposal-7/prereq/DeployAndConfigureFeeInfraHyperEVM.s.sol --rpc-url hyperevm --broadcast
```

> Note: two pieces of proposal 6's v4 configuration are not applied. `batchSetHookFamily`, assigning LBP and CCA hooks to family 255, because no HyperEVM hooks exist yet to list. `batchSetPairClassFee`, discounting stable-stable aggregator pairs, because candidates exist on HyperEVM but the list has not been chosen. Both are `onlyFeeSetter`, so adding either means adding it above transaction 26; afterwards they are governance actions needing no redeployment.

**Transactions**:

| Index          | Action                                                                    |
| -------------- | ------------------------------------------------------------------------- |
| 00             | Deploy `TokenJar`.                                                        |
| 01             | Deploy `WormholeReleaser`.                                                |
| 02             | Set `WormholeReleaser` as the releaser on `TokenJar`.                     |
| 03             | Transfer `TokenJar` ownership to governance.                              |
| 04             | Set `WormholeReleaser` threshold-setter to governance.                    |
| 05             | Transfer ownership of `WormholeReleaser` to governance.                   |
| 06             | Deploy `V3OpenFeeAdapter`.                                                |
| 07             | Set `V3OpenFeeAdapter` fee-setter to the deployer for configuration.      |
| 08             | Set `V3OpenFeeAdapter` default fee.                                       |
| 09, 10, 11, 12 | Set `V3OpenFeeAdapter` fee tier defaults.                                 |
| 13, 14, 15, 16 | Store `V3OpenFeeAdapter` fee tiers.                                       |
| 17             | Transfer `V3OpenFeeAdapter` fee-setter permission to governance.          |
| 18             | Transfer `V3OpenFeeAdapter` ownership to governance.                      |
| 19             | Deploy `V4FeeAdapter`.                                                    |
| 20             | Deploy `V4FeePolicy`.                                                     |
| 21             | Set `V4FeePolicy` on `V4FeeAdapter`.                                      |
| 22             | Set `V4FeePolicy` fee-setter to the deployer for configuration.           |
| 23             | Set `V4FeePolicy` fee buckets.                                            |
| 24             | Set `V4FeePolicy` flag rules.                                             |
| 25             | Set `V4FeePolicy` aggregator hook family default.                         |
| 26             | Transfer `V4FeePolicy` fee-setter permission to governance.               |
| 27             | Transfer `V4FeePolicy` ownership to governance.                           |
| 28             | Transfer `V4FeeAdapter` fee-setter permission to governance.              |
| 29             | Transfer `V4FeeAdapter` ownership to governance.                          |

**Verification**:

```bash
forge script script/proposal-7/prereq/DeployAndConfigureFeeInfraHyperEVM.s.sol --sig "check()" --rpc-url hyperevm
```

### 3. Write the proposal

**Overview**:

Reads both prerequisite deployments out of the record and writes the proposal to `./out/.seatbelt/HyperEVMFeeProposal.json` for Seatbelt. It does not broadcast; the `propose` call is made separately from that output. Run against Ethereum, where it also asserts that every target answers to the Timelock and that neither NTT contract knows HyperEVM yet.

**Foundry Script**:

[`./HyperEVMFees.s.sol`](./HyperEVMFees.s.sol)

**Shell Command**:

```bash
# from root directory of this repository:
forge script script/proposal-7/HyperEVMFees.s.sol --rpc-url mainnet
```

**Preflight**:

The HyperEVM half assumes the receiver trusts the Ethereum sender and already holds the v2 `feeToSetter`, the v3 `owner`, and the `PoolManager` `owner`. That handoff is a prerequisite for this proposal. Run `preflight()` against HyperEVM before proposing, since a failure otherwise surfaces only when the message is relayed after the vote:

```bash
forge script script/proposal-7/HyperEVMFees.s.sol --sig "preflight()" --rpc-url hyperevm
```

## Governance actions

### Ethereum actions

---

**OVERVIEW**:

Registers the HyperEVM `WormholeTransceiver` and `NttManager` as peers on their Ethereum counterparts, which proposal 4 deployed and the Timelock owns. This is what lets UNI burned on HyperEVM release on Ethereum. Without it the burn path does not complete.

**RELEVANT ADDRESSES**:

| Name                  | Network  | Address                                      | Description                             |
| --------------------- | -------- | -------------------------------------------- | --------------------------------------- |
| `nttManager`          | Ethereum | `0x6569925Aac77D6B8Bb085F31F9828ff80D5a0c44` | Ethereum NTT manager, from proposal 4   |
| `wormholeTransceiver` | Ethereum | `0x7597C40Fd3df66b750C14ad4D90524e247499011` | Ethereum transceiver, from proposal 4   |
| `timelock`            | Ethereum | `0x1a9C8182C09F50C8318d769245beA52c32BE35BC` | Owner of both, and the proposal executor |
| `NttManager`          | HyperEVM | recorded by step 1                           | Peer being registered                   |
| `WormholeTransceiver` | HyperEVM | recorded by step 1                           | Peer being registered                   |

**ACTIONS**:

- From the `Timelock`:
    - Set the HyperEVM `WormholeTransceiver` as a peer on the Ethereum `WormholeTransceiver`.
    - Set the HyperEVM `NttManager` as a peer on the Ethereum `NttManager`.

**BEFORE AND AFTER**:

```mermaid
---
config:
    theme: 'dark'
---
flowchart LR
    subgraph after[After Action]
        direction LR

        A_NttManager(NttManager)
        A_WormholeTransceiver(WormholeTransceiver)
        A_BNBChain(BNB Chain)
        A_Polygon(Polygon)
        A_HyperEVM(HyperEVM)

        A_NttManager --> A_BNBChain
        A_NttManager --> A_Polygon
        A_NttManager --> A_HyperEVM

        A_WormholeTransceiver --> A_BNBChain
        A_WormholeTransceiver --> A_Polygon
        A_WormholeTransceiver --> A_HyperEVM
    end

    subgraph before[Before Action]
        direction LR

        B_NttManager(NttManager)
        B_WormholeTransceiver(WormholeTransceiver)
        B_BNBChain(BNB Chain)
        B_Polygon(Polygon)

        B_NttManager --> B_BNBChain
        B_NttManager --> B_Polygon

        B_WormholeTransceiver --> B_BNBChain
        B_WormholeTransceiver --> B_Polygon
    end

    before:::before
    after:::after

    A_HyperEVM:::changed

    %% Link indices count across the whole diagram in declaration order.
    %% 2 and 5 are the two new HyperEVM peer registrations.
    linkStyle 2,5 stroke:#52b788

    classDef before fill:#202020,color:#fff,stroke:#59213f,stroke-width:4
    classDef after fill:#202020,color:#fff,stroke:#3d7d69,stroke-width:4
    classDef changed fill:#2d6a4f,stroke:#52b788,color:#fff
```

This proposal's changes (including prerequisite deployments) are in green. Both peer registrations happen on Ethereum, on contracts proposal 4 deployed.

### HyperEVM actions

---

**OVERVIEW**:

One Wormhole message carrying three calls, executed by the `UniswapWormholeMessageReceiver`, which owns all three protocol contracts. V3 sends fees to the factory owner, so activating v3 means transferring factory ownership to the `V3OpenFeeAdapter` rather than setting a collector.

**RELEVANT ADDRESSES**:

| Name                | Network  | Address                                      | Description                        |
| ------------------- | -------- | -------------------------------------------- | ---------------------------------- |
| `V2_FACTORY`        | HyperEVM | see [`Constants.sol`](./Constants.sol)       | Uniswap V2 Factory                 |
| `V3_FACTORY`        | HyperEVM | see [`Constants.sol`](./Constants.sol)       | Uniswap V3 Factory                 |
| `POOL_MANAGER`      | HyperEVM | see [`Constants.sol`](./Constants.sol)       | Uniswap V4 Pool Manager            |
| `WORMHOLE_RECEIVER` | HyperEVM | see [`Constants.sol`](./Constants.sol)       | Governance owned Wormhole receiver |
| `WORMHOLE_SENDER`   | Ethereum | `0xf5F4496219F31CDCBa6130B5402873624585615a` | Wormhole sender, owned by Timelock |
| `TokenJar`          | HyperEVM | recorded by step 2                           | Fee destination                    |
| `V3OpenFeeAdapter`  | HyperEVM | recorded by step 2                           | New V3 factory owner               |
| `V4FeeAdapter`      | HyperEVM | recorded by step 2                           | New protocol fee controller        |

**ACTIONS**:

- From `UniswapWormholeMessageReceiver`:
    - Set `UniswapV2Factory.feeTo` to `TokenJar`.
    - Set `UniswapV3Factory.owner` to `V3OpenFeeAdapter`.
    - Set `PoolManager.protocolFeeController` to `V4FeeAdapter`.

**BEFORE AND AFTER**:

```mermaid
---
config:
    theme: 'dark'
---
flowchart LR
    subgraph after[After Action]
        direction LR

        A_UniswapV2Factory(UniswapV2Factory)
        A_UniswapV3Factory(UniswapV3Factory)
        A_PoolManager(PoolManager)
        A_TokenJar(TokenJar)
        A_V3OpenFeeAdapter(V3OpenFeeAdapter)
        A_V4FeeAdapter(V4FeeAdapter)
        A_WormholeReceiver(WormholeReceiver)
        A_WormholeNTTManager(WormholeNTTManager)
        A_WormholeReleaser(WormholeReleaser)
        A_WormholeBridge((WormholeBridge))

        subgraph A_Core[Uniswap Core]
            A_UniswapV2Factory
            A_UniswapV3Factory
            A_PoolManager
        end

        A_WormholeNTTManager -->|"owner()"| A_WormholeReceiver
        A_WormholeNTTManager -.->|"bridge"| A_WormholeBridge
        A_WormholeReleaser -->|"owner()"| A_WormholeReceiver
        A_TokenJar -->|"owner()"| A_WormholeReceiver

        A_UniswapV2Factory -->|"feeTo()"| A_TokenJar
        A_UniswapV2Factory -->|"feeToSetter()"| A_WormholeReceiver

        A_UniswapV3Factory -->|"owner()"| A_V3OpenFeeAdapter
        A_V3OpenFeeAdapter -->|"owner()"| A_WormholeReceiver
        A_V3OpenFeeAdapter -->|"TOKEN_JAR()"| A_TokenJar

        A_PoolManager -->|"protocolFeeController()"| A_V4FeeAdapter
        A_PoolManager -->|"owner()"| A_WormholeReceiver
        A_V4FeeAdapter -->|"owner()"| A_WormholeReceiver

        A_WormholeReceiver -.->|"bridge"| A_WormholeBridge
    end

    subgraph before[Before Action]
        direction LR

        B_UniswapV2Factory(UniswapV2Factory)
        B_UniswapV3Factory(UniswapV3Factory)
        B_PoolManager(PoolManager)
        B_WormholeReceiver(WormholeReceiver)
        B_WormholeBridge((WormholeBridge))
        B_Z(0x00...00)

        subgraph B_Core[Uniswap Core]
            B_UniswapV2Factory
            B_UniswapV3Factory
            B_PoolManager
        end

        B_UniswapV2Factory -->|"feeTo()"| B_Z
        B_UniswapV2Factory -->|"feeToSetter()"| B_WormholeReceiver

        B_UniswapV3Factory -->|"owner()"| B_WormholeReceiver

        B_PoolManager -->|"protocolFeeController()"| B_Z
        B_PoolManager -->|"owner()"| B_WormholeReceiver

        B_WormholeReceiver -.->|"bridge"| B_WormholeBridge
    end

    before:::before
    after:::after
    A_Core:::core
    B_Core:::core

    A_TokenJar:::changed
    A_V3OpenFeeAdapter:::changed
    A_V4FeeAdapter:::changed

    %% Link indices count across the whole diagram in declaration order.
    %% 4 = feeTo(), 6 = v3 factory owner(), 9 = protocolFeeController().
    linkStyle 4,6,9 stroke:#52b788

    classDef before fill:#202020,color:#fff,stroke:#59213f,stroke-width:4
    classDef after fill:#202020,color:#fff,stroke:#3d7d69,stroke-width:4
    classDef core fill:#202020,color:#fff,stroke:#f50db4,stroke-width:4
    classDef changed fill:#2d6a4f,stroke:#52b788,color:#fff
```

This proposal's changes (including prerequisite deployments) are in green.

## Relaying the message

Wormhole does not deliver the HyperEVM message. After the proposal executes, the VAA for the HyperEVM action has to be fetched from Wormhole's API and passed to `receiveMessage` on the receiver. Proposal 4 did this with a finalizer script carrying the VAA bytes; the equivalent here can only be written once there is a VAA.

Someone, potentially Wormhole, will sometimes batch-relay messages themselves. Nothing in that path logs an observable event or shows as a transaction on Etherscan-style explorers, so a later relay attempt reverts as a replay and looks like a failure even though the message already executed.
