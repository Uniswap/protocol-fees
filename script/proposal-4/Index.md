# Proposal-4

- [Proposal-4](#proposal-4)
  - [Definitions](#definitions)
  - [Abstract](#abstract)
  - [Action Ordering](#action-ordering)
  - [Wormhole Context](#wormhole-context)
    - [Transfer UNI to BNBChain Flow](#transfer-uni-to-bnbchain-flow)
    - [Transfer SyntheticNttUni to Ethereum Flow](#transfer-syntheticnttuni-to-ethereum-flow)
    - [Burn UNI via Releaser from BNBChain Flow](#burn-uni-via-releaser-from-bnbchain-flow)
    - [On Wormhole ERC1967 Proxies](#on-wormhole-erc1967-proxies)
  - [Polygon Context](#polygon-context)
  - [Prerequisite Actions](#prerequisite-actions)
    - [1. Deploy Wormhole Infra BNB Chain](#1-deploy-wormhole-infra-bnb-chain)
    - [2. Deploy Wormhole Infra Ethereum](#2-deploy-wormhole-infra-ethereum)
    - [3. Configure Wormhole Infra BNB Chain](#3-configure-wormhole-infra-bnb-chain)
    - [4. Configure Wormhole Infra Ethereum](#4-configure-wormhole-infra-ethereum)
    - [5. Deploy and Configure Fee Infra BNB Chain](#5-deploy-and-configure-fee-infra-bnb-chain)
    - [TODO: Polygon](#todo-polygon)
  - [Governance Actions](#governance-actions)
    - [Celo Actions](#celo-actions)
    - [BNB Chain Actions](#bnb-chain-actions)
    - [Polygon Actions](#polygon-actions)

## Definitions

- Home chain: Ethereum L1
- Foreign chain: Generic name for non-Ethereum L1 chain.
- Local chain: Refers to the same chain in whatever context in which it's mentioned.
- UNI:
    - For Ethereum, this is the canonical Uniswap token.
    - For foreign chains, this is a synthetic Uniswap token.
- TokenJar: Contract which "owns" the Uniswap V2, V3, and V4 protocols and collects protocol fees.
- Releaser: Contract which releases a basket of tokens from TokenJar in exchange for UNI to burn.
- Fee Collection Infrastructure: UNI, TokenJar, and Releaser.
- Burn:
    - For canonical UNI, this is a `transfer` to `address(0xdead)`.
    - For synthetic UNI, this is a local chain `burn` to enable an unlock on the home chain.

## Abstract

Proposal 4 activates fee switches on Celo, BNB Chain, and Polygon. Celo fee collection
infrastructure has already been deployed and configured for the OP canonical bridge, it needs only
an ownership transition. BNB Chain does not have fee collection infrastructure, there are
prerequisite actions which must be taken before governance can enact the ownership transition.
Polygon also does not have fee collection infrastructure, there are prerequsite actions which must
be taken before governance can enact the ownership transition.

## Action Ordering

Actions must be taken in this order.

1. Deploy Wormhole Infra BNB Chain
2. Deploy Wormhole Infra Ethereum
3. Configure Wormhole Infra BNB Chain
4. Configure Wormhole Infra Ethereum
5. Deploy and Configure Fee Infra BNB Chain
6. Governance Proposal

For members of governance, the prerequisite action sections are unnecessary, as they can be handled
permissionlessly. See [Governance Actions](#governance-actions).

Dependency graph:

```mermaid
flowchart BT
    DWIB(["Deploy Wormhole Infra (BNB)"]):::on_bnb
    DWIE(["Deploy Wormhole Infra (ETH)"]):::on_eth
    CWIB(["Conf Wormhole Infra (BNB)"]):::on_bnb
    CWIE(["Conf Wormhole Infra (ETH)"]):::on_eth
    DCFIB(["Deploy/Conf Fee Infra (BNB)"]):::on_bnb
    DCFIP(["Deploy/Conf Fee Infra (POL)"]):::on_pol
    GA(["Governance Actions"]):::on_eth

    GA      -->|requires| DCFIB
    GA      -->|requires| DCFIP
    DCFIB   -->|requires| CWIB
    DCFIB   -->|requires| CWIE
    CWIB    -->|requires| DWIB
    CWIB    -->|requires| DWIE
    CWIE    -->|requires| DWIB
    CWIE    -->|requires| DWIE

    classDef on_bnb fill:#a0814a,color:#fff
    classDef on_eth fill:#00567b,color:#fff
    classDef on_pol fill:#603e68,color:#fff

    linkStyle 0,1,2,3,4,5,6,7 stroke:#fff,stroke-width:4px
```

## Wormhole Context

Wormhole team suggests integrators use the new "Native Token Transfer" (Ntt) mechanism for
multichain token management.

We use the "Hub and Spoke" model such that the canonical (Ethereum) UNI represents the "Hub" and the
foreign chain deployments of a synthetic UNI (`SyntheticNttUni`) are the "Spokes".

> In simple terms, this is a "lock, mint, and burn" system where canonical UNI is locked on Ethereum
> so a synthetic UNI can be minted on a foreign chain.

This system requires integrators (us) to deploy on Ethereum and BNB Chain a
`WormholeTransceiver` to process messages and a Wormhole `NttManager` to manage transceivers and
handle other peripheral logic such as message attestation and rate limiting (although we eschew rate
limiting for simplicity of deployment and authority management). The `WormholeTransceiver`
deployments on Ethereum and BNB Chain be mutually aware of one another, as do the `NttManager`
deployments on Etheruem and BNB Chain. Additionally, for each chain, the `NttManager` must store the
local `WormholeTransceiver` deployment in its own registry.

Finally, for BNB Chain, there must be a `SyntheticNttUni` deployment which allows mint and burn
authority to the `NttManager` such that it may process mints and burns as appropriate.

### Transfer UNI to BNBChain Flow

```mermaid
flowchart LR
    ETH_WT([WormholeTransceiver])
    ETH_NTT([NttManager])
    ETH_UNI([UNI])
    BNB_WT([WormholeTransceiver])
    BNB_NTT([NttManager])
    BNB_UNI([SyntheticNttUni])

    subgraph Ethereum
        direction LR
        ETH_UNI -->|locked to| ETH_NTT
        ETH_NTT -->|sends msg| ETH_WT
    end

    Ethereum -.->|Wormhole| BNBChain

    subgraph BNBChain
        direction LR
        BNB_WT -->|forward msg| BNB_NTT
        BNB_NTT -->|mint| BNB_UNI
    end

    Ethereum:::on_eth
    BNBChain:::on_bnb

    linkStyle default stroke:#fff,stroke-width:4px
    classDef default fill:#202020,color:#fff
    classDef on_bnb fill:#a0814a,color:#fff
    classDef on_eth fill:#498fb6,color:#fff
```

### Transfer SyntheticNttUni to Ethereum Flow

```mermaid
flowchart RL
    ETH_WT([WormholeTransceiver])
    ETH_NTT([NttManager])
    ETH_UNI([UNI])
    BNB_WT([WormholeTransceiver])
    BNB_NTT([NttManager])
    BNB_UNI([SyntheticNttUni])

    subgraph Ethereum
        direction RL
        ETH_WT -->|forward msg| ETH_NTT
        ETH_NTT -->|unlocked from| ETH_UNI
    end

    BNBChain -.->|Wormhole| Ethereum

    subgraph BNBChain
        direction RL
        BNB_UNI -->|burn to| BNB_NTT
        BNB_NTT -->|send msg| BNB_WT
    end

    Ethereum:::on_eth
    BNBChain:::on_bnb

    linkStyle default stroke:#fff,stroke-width:4px
    classDef default fill:#202020,color:#fff
    classDef on_bnb fill:#a0814a,color:#fff
    classDef on_eth fill:#498fb6,color:#fff
```

### Burn UNI via Releaser from BNBChain Flow

```mermaid
flowchart RL
    ETH_WT([WormholeTransceiver])
    ETH_NTT([NttManager])
    ETH_UNI([UNI])
    BNB_WT([WormholeTransceiver])
    BNB_NTT([NttManager])
    BNB_UNI([SyntheticNttUni])
    BNB_R([Releaser])
    BNB_TJ([TokenJar])
    BNB_V2([Uniswap V2])
    BNB_V3([Uniswap V3])
    BNB_V4([Uniswap V4])

    subgraph Ethereum
        direction RL
        ETH_WT -->|forward msg| ETH_NTT
        ETH_NTT -->|burn to 0xDEAD| ETH_UNI
    end

    BNBChain -.->|Wormhole| Ethereum

    subgraph BNBChain
        direction RL
        BNB_V2 -->|sends fees| BNB_TJ
        BNB_V3 -->|sends fees| BNB_TJ
        BNB_V4 -->|sends fees| BNB_TJ
        BNB_TJ -->|releases to| BNB_R
        BNB_R -->|"bridge to 0xDEAD"| BNB_UNI
        BNB_UNI -->|burn to| BNB_NTT
        BNB_NTT -->|send msg| BNB_WT
    end

    Ethereum:::on_eth
    BNBChain:::on_bnb

    linkStyle default stroke:#fff,stroke-width:4px
    classDef default fill:#202020,color:#fff
    classDef on_bnb fill:#a0814a,color:#fff
    classDef on_eth fill:#498fb6,color:#fff
```

### On Wormhole ERC1967 Proxies

We generally avoid upgradeable proxies as they pose a substantial risk to both the users and to the
upgrade authorities to these contracts.

Unfortunately, Wormhole only provides `NttManagerNoRateLimiting` and `WormholeTransceiver` instances
which are programmed to be used as implementations for a proxy. Additionally, Wormhole has
intertwined the authority to upgrade the proxy with the authority to perform maintenance, migration,
and registry updates which may be necessary in time.

**To avoid a substantial refactoring of the wormhole logic and opening new security risks, we use**
**their implementations for now.**

To mitigate the risks of this, however, the proxy ownership is granted to the deployer account
during the prerequisite transactions and then transferred to governance BEFORE the governance
proposal. On Ethereum, the proxy ownership is transferred to `Timelock`, which is owned by
governance. On BNB Chain the proxy ownership is transferred to `UniswapWormholeMessageReceiver`,
which is guarded such that only governance can send it messages through wormhole.

## Polygon Context

**NOTICE: Polygon documentation is incorrect. Notes are kept here for now.**

Polygon maintains a whitelist of allowed state senders and receivers. Listing
addresses here for now so we know what exists where.

Ethereum:

- `StateSender`: `0x28e4F3a7f651294B9564800b2D01f35189A5bFbE`
- `DepositManagerProxy`: `0x401F6c983eA34274ec46f84D70b31C151321188b`
  - `DepositManager`: `0xb00aa68b87256e2f22058fb2ba3246eec54a44fc` (implemenation)
- `RootChainManagerProxy`: `0xA0c68C638235ee32657e8f720a23ceC1bFc77C77`
  - `RootChainManager`: `0xf0235dca8fb0d3999685724dcbb9dd00c5d62dfa` (implemenation)
- `FxRoot`: `0xfe5e5D361b2ad62c541bAb87C45a0B9B018389a2`

Polygon:

- `System`: `0x0000000000000000000000000000000000001001`
- `ChildChain`: `0xD9c7C4ED4B66858301D0cb28Cc88bf655Fe34861`
  - `SafeProxy`: `0x3a635c48836E7c0B9aEB378640B0BfD516985cF5` (owner)
- `ChildChainManagerProxy`: `0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa`
  - `ChainChildManager`: `0xa40fc0782bee28dd2cf8cb4ac2ecdb05c537f1b5` (implementation)
- `EthereumProxy`: `0x8a1B966aC46F42275860f905dbC75EfBfDC12374`
  - this is not actually a proxy, unsure why this is named as such
- `FxChild`: `0x8397259c983751DAf40400790063935a11afa28a`

`System` whitelists sender/receiver pairs:

- `FxRoot` -> `FxChild`: message bridge for governance
- `DepositManagerProxy` -> `ChildChain`: token bridging (5yrs old, may be outdated)
- `RootChainManagerProxy` -> `ChildChainManagerProxy`: uncertain
- (~7 other whitelisted items, TODO: add these)

Governance order of ops:

- `Timelock` (owned by gov) calls `FxRoot`
- `FxRoot` calls `StateSender`
- `StateSender` logs `StateSynced` event
- polygon node calls on behalf of `System`
- `System` calls `FxChild`
- `FxChild` calls `EthereumProxy` (owned by gov)
- `EthereumProxy` decodes info and multicalls to protocol

Interfaces:

```solidity
// -- ethereum
interface FxRoot {
    function sendMessageToChild(address _receiver, bytes calldata _data) external;
}

interface StateSender {
    function syncState(address receiver, bytes calldata data) external;
}

// -- polygon
interface FxChild {
    function onStateReceive(uint256 stateId, bytes calldata _data) external;
}

interface EthereumProxy {
    function processMessageFromRoot(uint256,address sender,bytes memory message) external;
}
```

Flow:

```mermaid
flowchart LR
    Bridge{Bridge}
    subgraph Polygon
        direction LR
        System([System])
        FxChild([FxChild])
        EthereumProxy([EthereumProxy])
        V2Factory([V2Factory])
        V3Factory([V3Factory])
        PoolManager([PoolManager])

        System -->|onStateReceive| FxChild
        FxChild -->|processMessageFromRoot| EthereumProxy
        EthereumProxy -->|call| V2Factory
        EthereumProxy -->|call| V3Factory
        EthereumProxy -->|call| PoolManager
    end

    subgraph Ethereum
        direction LR
        Governance([Governance])
        FxRoot([FxRoot])
        StateSender([StateSender])

        Governance -->|sendMessageToChild| FxRoot
        FxRoot -->|syncState| StateSender
    end

    StateSender -.-> Bridge
    Bridge -.-> System

    Ethereum:::on_eth
    Polygon:::on_pol

    linkStyle default stroke:#fff,stroke-width:4px
    classDef default fill:#202020,color:#fff
    classDef on_pol fill:#84608c,color:#fff
    classDef on_eth fill:#498fb6,color:#fff
```

## Prerequisite Actions

### 1. Deploy Wormhole Infra BNB Chain

**Overview**:

On BNB Chain we deploy `SyntheticNttUni`, `NttManagerNoRateLimiting`, `WormholeTransceiver`, and two
`ERC1967Proxy` contracts. We set the implementations of the proxies to be `NttManagerNoRateLimiting`
and `WormholeTransceiver`, but we do not use a proxy for `SyntheticNttUni`. From here we initialize
the proxies, register the `WormholeTransceiver` proxy to the `NttManagerNoRateLimiting` proxy's
transceiver registry, set the `SyntheticNttUni`'s minting authority to `NttManagerNoRateLimiting`,
and transfer ownership of `SyntheticNttUni` to `UniswapWormholeMessageReceiver`.

> Note: The addresses deployed are needed in subsequent prerequisite scripts, so ownership of the
> proxy is transferred in the [`ConfigWormholeInfraBNBChain`](#3-configure-wormhole-infra-bnb-chain)

**Foundry Script**:

[`./deploys/DeployWormholeInfraBNBChain.s.sol`](./deploys/DeployWormholeInfraBNBChain.s.sol)

**Shell Command**:

```bash
# from root directory of this repository:
forge script script/proposal-4/deploys/DeployWormholeInfraBNBChain.s.sol:DeployWormholeInfraBNBChainScript
```

**Transactions**:

| Index | Action                                                               |
| ----- | -------------------------------------------------------------------- |
| 00    | Deploy SyntheticNttUni.                                              |
| 01    | Deploy NttManager implementation.                                    |
| 02    | Deploy NttManager proxy.                                             |
| 03    | Initialize NttManager proxy.                                         |
| 04    | Deploy WormholeTransceiver implementation.                           |
| 05    | Deploy WormholeTransceiver proxy.                                    |
| 06    | Initialize WormholeTransceiver proxy.                                |
| 07    | Set NttManager proxy's transceiver to the WormholeTransceiver proxy. |
| 08    | Set the threshold of transceiver attestation redundancy.             |
| 09    | Set SyntheticNttUniNtt mint authority to NttManager proxy.           |
| 10    | Transfer ownership of SyntheticNttUni to governance.                 |

### 2. Deploy Wormhole Infra Ethereum

**Overview**:

On Etheruem, we deloy `NttManagerNoRateLimiting`, `WormholeTransceiver` and two `ERC1967Proxy`
contracts. We set the implementations of the proxies to be `NttManagerNoRateLimiting` and
`WormholeTransceiver`. From here we initialize the proxies, register the `WormholeTransceiver` proxy
to the `NttManagerNoRateLimiting` transceiver registry, then point the `NttManagerNoRateLimiting` at
the canonical UNI. 

> Note: The addresses deployed are needed in subsequent prerequisite scripts, so ownership of the
> proxy is transferred in the [`ConfigWormholeInfraEthereum`](#4-configure-wormhole-infra-ethereum)

**Foundry Script**:

[`./deploys/DeployWormholeInfraEthereum.s.sol`](./deploys/DeployWormholeInfraEthereum.s.sol)

**Shell Command**:

```bash
# from root directory of this repository:
forge script script/proposal-4/deploys/DeployWormholeInfraEthereum.s.sol:DeployWormholeInfraEthereumScript
```

**Transactions**:

| Index | Action                                                               |
| ----- | -------------------------------------------------------------------- |
| 00    | Deploy NttManager implementation.                                    |
| 01    | Deploy NttManager proxy.                                             |
| 02    | Initialize NttManager proxy.                                         |
| 03    | Deploy WormholeTransceiver implementation.                           |
| 04    | Deploy WormholeTransceiver proxy.                                    |
| 05    | Initialize WormholeTransceiver proxy.                                |
| 06    | Set NttManager proxy's transceiver to the WormholeTransceiver proxy. |
| 07    | Set the threshold of transceiver attestation redundancy.             |

### 3. Configure Wormhole Infra BNB Chain

**Overview**:

We load the addresses from the `broadcast/` directory, which is where the prerequisite deployment
script outputs should be writen. Default files are as follows:

```solidity
string constant BNB_DEPLOY_PATH = "broadcast/DepoyWormholeInfraBNBChain.s.sol/56/run-latest.json";
string constant ETH_DEPLOY_PATH = "broadcast/DeployWormholeInfraEthereum.s.sol/1/run-latest.json";
```

We perform a myriad of contract and state checks before proceeding to minimize risks of malformed or
incorrect data.

From here, we set the `WormholeTransceiver` proxy deployed on Ethereum as a "Wormhole peer" on the
`WormholeTransceiver` proxy deployed on BNB Chain, then we set the `NttManagerNoRateLimiting` proxy
deployed on Ethereum as a "peer" on the `NttManagerNoRateLimiting` proxy deployed on BNB Chain.
Finally we transfer proxy ownership to `Timelock`.

**Foundry Script**:

[`./deploys/ConfigWormholeInfraBNBChain.s.sol`](./deploys/ConfigWormholeInfraBNBChain.s.sol)

**Shell Command**:

```bash
# from root directory of this repository:
forge script script/proposal-4/deploys/ConfigWormholeInfraBNBChain.s.sol:ConfigWormholeInfraBNBChainScript
```

**Transactions**:

| Index | Action                                                                     |
| ----- | -------------------------------------------------------------------------- |
| 00    | Set BNBChain WormholeTransceiver proxy as a peer on the BNBChain Chain Id. |
| 01    | Set the NttManager Proxy on Ethereum as a peer.                            |
| 02    | Transfer proxy ownership to Timelock.                                      |


### 4. Configure Wormhole Infra Ethereum

**Overview**:

We load the addresses from the `broadcast/` directory, which is where the prerequisite deployment
script outputs should be writen. Default files are as follows:

```solidity
string constant BNB_DEPLOY_PATH = "broadcast/DepoyWormholeInfraBNBChain.s.sol/56/run-latest.json";
string constant ETH_DEPLOY_PATH = "broadcast/DeployWormholeInfraEthereum.s.sol/1/run-latest.json";
```

We perform a myriad of contract and state checks before proceeding to minimize risks of malformed or
incorrect data.

From here, we set the `WormholeTransceiver` proxy deployed on BNB Chain as a "Wormhole peer" on the
`WormholeTransceiver` proxy deployed on Ethereum, then we set the `NttManagerNoRateLimiting` proxy
deployed on BNB Chain as a "peer" on the `NttManagerNoRateLimiting` proxy deployed on Ethereum.
Finally we transfer proxy ownership to `UniswapWormholeMessageReceiver`.

**Foundry Script**:

[`./deploys/ConfigWormholeInfraEthereum.s.sol`](./deploys/ConfigWormholeInfraEthereum.s.sol)

**Shell Command**:

```bash
# from root directory of this repository:
forge script script/proposal-4/deploys/ConfigWormholeInfraEthereum.s.sol:ConfigWormholeInfraEthereumScript
```

**Transactions**:

| Index | Action                                                                     |
| ----- | -------------------------------------------------------------------------- |
| 00    | Set BNBChain WormholeTransceiver proxy as a peer on the BNBChain Chain Id. |
| 01    | Set the NttManager Proxy on Ethereum as a peer.                            |
| 02    | Transfer proxy ownership to UniswapWormholeMessageReceiver.                |

### 5. Deploy and Configure Fee Infra BNB Chain

**Overview**:

We load the addresses from the `broadcast/` directory, which is where the prerequisite deployment
script outputs should be writen. Default files are as follows:

```solidity
string constant BNB_DEPLOY_PATH = "broadcast/DepoyWormholeInfraBNBChain.s.sol/56/run-latest.json";
```

We perform a myriad of contract and state checks before proceeding to minimize risks of malformed or
incorrect data.

From here, we deploy the `TokenJar` and `WormholeReleaser`, set the `WormholeReleaser` to be the
releaser for `TokenJar`, transfer ownership of each to governance, threshold setting permission to
governance, delpoy the `V3OpenFeeAdapter` and set default fee tiers, then transfer the fee setting
permission and ownership to governance.

**Foundry Script**:

[`./deploys/DeployAndConfigureFeeInfraBNBChain.s.sol`](./deploys/DeployAndConfigureFeeInfraBNBChain.s.sol)

**Shell Command**:

```bash
# from root directory of this repository:
forge script script/proposal-4/deploys/DeployAndConfigureFeeInfraBNBChain.s.sol:DeployAndConfigureFeeInfraBNBChainScript
```

**Transactions**:

| Index | Action                                                                                 |
| ----- | -------------------------------------------------------------------------------------- |
| 00    | Deploy `TokenJar`.                                                                     |
| 01    | Deploy `WormholeReleaser`.                                                             |
| 02    | Set `WormholeReleaser` as the releaser on `TokenJar`.                                  |
| 03    | Transfer `TokenJar` ownership to `UniswapWormholeMessageReceiver`.                     |
| 04    | Set `WormholeReleaser` threshold setter to `UniswapWormholeMessageReceiver`.           |
| 05    | Transfer ownership of `WormholeReleaser` to `UniswapWormholeMessageReceiver`.          |
| 06    | Deploy `V3OpenFeeAdapter`.                                                             |
| 07    | Set `V3OpenFeeAdapter` fee setter to the deployer for configuration.                   |
| 08    | Set `V3OpenFeeAdapter` default fee.                                                    |
| 09    | Set `V3OpenFeeAdapter` fee tier defaults.                                              |
| 10    | Set `V3OpenFeeAdapter` fee tier defaults.                                              |
| 11    | Set `V3OpenFeeAdapter` fee tier defaults.                                              |
| 12    | Set `V3OpenFeeAdapter` fee tier defaults.                                              |
| 13    | Store `V3OpenFeeAdapter` fee tiers.                                                    |
| 14    | Store `V3OpenFeeAdapter` fee tiers.                                                    |
| 15    | Store `V3OpenFeeAdapter` fee tiers.                                                    |
| 16    | Store `V3OpenFeeAdapter` fee tiers.                                                    |
| 17    | Transfer `V3OpenFeeAdapter` fee setter permission to `UniswapWormholeMessageReceiver`. |
| 18    | Transfer `V3OpenFeeAdapter` ownership to `UniswapWormholeMessageReceiver`.             |


### TODO: Polygon

## Governance Actions

Governance takes five actions; one for Celo, one for BNB Chain, and three for Polygon. The actions
on Celo and BNB Chain contain multiple batched operations but Polygon cannot handled batched
operations.

### Celo Actions

---

**OVERVIEW**:

This action sets the fee collector of `UniswapV2Factory` to `TokenJar`, transfers ownership of
`UniswapV2Factory` and `PoolManager` to Optimism `CrossChainAccount`, and transfers ownerhsip of
`UniswapV3Factory` to `V3OpenFeeAdapter`.

**ACTIONS**:

- From `UniswapWormholeMesageReceiver`:
    - Set`UniswapV2Factory.feeTo` to `TokenJar`.
    - Set`UniswapV2Factory.feeToSetter` to `CrossChainAccout`.
    - Set`UniswapV3Factory.owner` to `V3OpenFeeAdapter`.
    - Set`PoolManager.owner` to `CrossChainAccout`.

**BEFORE AND AFTER**:

```mermaid
flowchart LR
    subgraph after
        direction LR

        A_UniswapV2Factory(UniswapV2Factory)
        A_UniswapV3Factory(UniswapV3Factory)
        A_PoolManager(PoolManager)
        A_TokenJar(TokenJar)
        A_CrossChainAccount(CrossChainAccount)
        A_V3OpenFeeAdapter(V3OpenFeeAdapter)
        A_OptimismBridge((OptimismBridge))

        A_UniswapV2Factory -->|feeTo| A_TokenJar
        A_UniswapV2Factory -->|feeToSetter| A_CrossChainAccount
        A_UniswapV3Factory -->|owner| A_V3OpenFeeAdapter
        A_TokenJar -->|owner| A_CrossChainAccount
        A_V3OpenFeeAdapter -->|owner| A_CrossChainAccount
        A_PoolManager -->|owner| A_CrossChainAccount

        A_CrossChainAccount -.-> A_OptimismBridge

    end

    subgraph before
        direction LR

        B_UniswapV2Factory(UniswapV2Factory)
        B_UniswapV3Factory(UniswapV3Factory)
        B_PoolManager(PoolManager)
        B_TokenJar(TokenJar)
        B_CrossChainAccount(CrossChainAccount)
        B_V3OpenFeeAdapter(V3OpenFeeAdapter)
        B_WormholeReceiver(WormholeReceiver)
        B_WormholeBridge((WormholeBridge))
        B_OptimismBridge((OptimismBridge))
        B_Z(0x00..00)

        B_UniswapV2Factory -->|feeTo| B_Z
        B_UniswapV2Factory -->|feeToSetter| B_WormholeReceiver
        B_UniswapV3Factory -->|owner| B_WormholeReceiver
        B_PoolManager -->|owner| B_WormholeReceiver
        B_TokenJar -->|owner| B_CrossChainAccount
        B_V3OpenFeeAdapter -->|owner| B_CrossChainAccount

        B_WormholeReceiver -.-> B_WormholeBridge
        B_CrossChainAccount -.-> B_OptimismBridge
    end

    before:::before
    after:::after

    linkStyle default stroke:#fff,stroke-width:4px
    classDef default fill:#202020,color:#fff
    classDef before fill:#59213f,color:#fff
    classDef after fill:#3d7d69,color:#fff
```

### BNB Chain Actions

---

**OVERVIEW**:

This action sets the fee collector of `UniswapV2Factory` to `TokenJar`, transfers ownership of
`UniswapV3Factory` to `V3OpenFeeAdapter`.

**ACTIONS**:

- From `UniswapWormholeMesageReceiver`:
    - Set `UniswapV2Factory.feeTo` to `TokenJar`.
    - Set `UniswapV3Factory.owner` to `V3OpenFeeAdapter`.

**BEFORE AND AFTER**:

```mermaid
flowchart LR
    subgraph after
        direction LR

        A_UniswapV2Factory(UniswapV2Factory)
        A_UniswapV3Factory(UniswapV3Factory)
        A_PoolManager(PoolManager)
        A_TokenJar(TokenJar)
        A_V3OpenFeeAdapter(V3OpenFeeAdapter)
        A_WormholeReceiver(WormholeReceiver)
        A_WormholeBridge((WormholeBridge))

        A_UniswapV2Factory -->|feeTo| A_TokenJar
        A_UniswapV2Factory -->|feeToSetter| A_WormholeReceiver
        A_UniswapV3Factory -->|owner| A_V3OpenFeeAdapter
        A_TokenJar -->|owner| A_WormholeReceiver
        A_V3OpenFeeAdapter -->|owner| A_WormholeReceiver
        A_PoolManager -->|owner| A_WormholeReceiver

        A_WormholeReceiver -.-> A_WormholeBridge

    end

    subgraph before
        direction LR

        B_UniswapV2Factory(UniswapV2Factory)
        B_UniswapV3Factory(UniswapV3Factory)
        B_PoolManager(PoolManager)
        B_TokenJar(TokenJar)
        B_V3OpenFeeAdapter(V3OpenFeeAdapter)
        B_WormholeReceiver(WormholeReceiver)
        B_WormholeBridge((WormholeBridge))
        B_Z(0x00..00)

        B_UniswapV2Factory -->|feeTo| B_Z
        B_UniswapV2Factory -->|feeToSetter| B_WormholeReceiver
        B_UniswapV3Factory -->|owner| B_WormholeReceiver
        B_PoolManager -->|owner| B_WormholeReceiver
        B_TokenJar -->|owner| B_WormholeReceiver
        B_V3OpenFeeAdapter -->|owner| B_WormholeReceiver

        B_WormholeReceiver -.-> B_WormholeBridge
    end

    before:::before
    after:::after

    linkStyle default stroke:#fff,stroke-width:4px
    classDef default fill:#202020,color:#fff
    classDef before fill:#59213f,color:#fff
    classDef after fill:#3d7d69,color:#fff
```

### Polygon Actions

---

**OVERVIEW**:

TODO

**ACTIONS**:

TODO
