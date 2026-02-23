# Uniswap Fee Collection

_A unified system for collecting and converting fees from arbitrary revenue sources on arbitrary chains._

## Table of Contents

- [Overview](#overview)
- [Goals](#goals)
- [Architecture](#architecture)
- [Economic Incentives](#economic-incentives)
- [Fault Tolerance](#fault-tolerance)
- [Deployment Architecture](#deployment-architecture)
- [Development](#development)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
  - [Testing](#testing)
  - [Project Structure](#project-structure)
- [Governance Proposal](#governance-proposal)
- [Security](#security)
- [Future Development](#future-development)
  - [Protocol Fee Auctions](#protocol-fee-auctions)
  - [Additional Protocol Support](#additional-protocol-support)
  - [Cross-chain Expansion](#cross-chain-expansion)
- [Contributing](#contributing)
- [License](#license)
- [Support](#support)

## Overview

Uniswap Fee Collection is a maximally fault-tolerant system designed to collect fees from any revenue source on any blockchain and convert them efficiently. The system uses competitive economic incentives to ensure timely fee collection while maintaining decentralized governance through immutable smart contracts.

## Goals

- **Universal Support**: Collect fees from arbitrary revenue sources across arbitrary chains
- **Maximum Fault Tolerance**: Recover from chain downtime, bridge failures, and other infrastructure issues
- **Economic Efficiency**: Competitive mechanisms ensure optimal fee collection and conversion

## Architecture

The Uniswap system consists of three core layers that work together across all supported chains:

### 1. Token Jar

Each chain deploys a local **Token Jar** - an immutable smart contract that serves as the collection point for all fees on that chain.

```
Fee Sources → Token Jar → Releaser → Fee Conversion
```

**Key Properties:**

- **Universal Collector**: Receives fees from all sources on the chain
- **Single Admin**: Only the `releaser` can withdraw assets
- **Atomic Operations**: Full balance transfers only

The Token Jar defines one role: the `releaser`, which can atomically transfer the full balance of specified assets to a recipient address.

### 2. Fee Sources

Fee Sources are adapter contracts that channel fees from various protocols into the local Token Jar. They handle the diversity of fee collection mechanisms across different protocols.

#### Push vs Pull Models

**Push Sources** (e.g., Uniswap V2):

- Fees automatically flow to Token Jar
- Direct integration with protocol fee recipients
- Minimal ongoing maintenance

**Pull Sources** (e.g., Uniswap V3/V4):

- Require explicit collection calls
- Adapter contracts enable permissionless collection
- Anyone can trigger fee collection to Token Jar

#### Supported Protocols

**Uniswap V2**

- LP tokens minted directly to Token Jar
- 1/6 of swap fees collected as protocol revenue
- Zero additional infrastructure required

**Uniswap V3**

- V3FeeAdapter contract owns factory privileges
- Permissionless protocol fee collection
- Configurable fee rates per fee tier

**Uniswap V4 (TBD)**

- V4FeeAdapter as ProtocolFeeAdapter
- Not included as part of the initial fee enablement

### 3. Releasers

Releasers are smart contracts that serve as the `releaser` for Token Jars. They implement the business logic for converting collected fees into protocol value.

#### UNI Burn (Mainnet)

On Ethereum mainnet where UNI tokens exist:

```
Searcher → Pay UNI → Releaser → Release Assets → Burn UNI
```

**Mechanism:**

1. Searcher pays a fixed UNI amount to Releaser
2. Releaser releases Token Jar contents to searcher's specified recipient
3. UNI tokens are burned (sent to `0xdead`), reducing total supply
4. Searcher profits from asset value exceeding UNI burn cost

#### Cross-Chain UNI Burn (OP Stack L2s)

For OP Stack L2 chains (Unichain, Optimism, Base, etc.) where only bridged UNI exists:

```
┌─────────────────────────────────────────────────────────────────┐
│                          L2 (Unichain)                          │
│                                                                 │
│  Searcher → Pay Bridged UNI → OptimismBridgedResourceFirepit   │
│                                      │                          │
│                              ┌───────┴───────┐                  │
│                              │               │                  │
│                        Release Assets   Bridge Withdrawal       │
│                        to Recipient     (L2→L1)                │
│                                              │                  │
└──────────────────────────────────────────────│──────────────────┘
                                               │
                                        7-day challenge
                                            period
                                               │
                                               ▼
┌──────────────────────────────────────────────────────────────────┐
│                       Ethereum Mainnet (L1)                      │
│                                                                  │
│              L1StandardBridge → Transfer UNI → 0xdead (Burn)    │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

**Mechanism:**

The `OptimismBridgedResourceFirepit` implements a two-stage burn process:

**Stage 1 - L2 Collection:**

1. Searcher calls `release()` with the current nonce, assets to release, and recipient
2. Searcher pays a fixed amount of bridged UNI tokens
3. UNI is transferred to the Firepit contract (not burned yet)
4. Token Jar contents are released to the searcher's specified recipient

**Stage 2 - L1 Bridge & Burn:**

5. The `_afterRelease()` hook automatically initiates an L2→L1 bridge withdrawal
6. Bridged UNI is burned on L2 via the L2StandardBridge
7. A cross-domain message is queued for L1
8. After the 7-day challenge period, L1 UNI is transferred to `0xdead`

**Key Properties:**

- **Same Economics**: Searchers profit when fee asset value exceeds UNI threshold cost
- **Nonce Protection**: Sequential nonces prevent front-running and ensure deterministic ordering
- **Fault Tolerant**: If bridge is unavailable, fees safely accumulate in TokenJar until recovery
- **Native Bridge Security**: Uses Optimism's canonical bridge infrastructure

**Configuration:**

| Parameter             | Value       | Description                         |
| --------------------- | ----------- | ----------------------------------- |
| RESOURCE              | Bridged UNI | OptimismMintableERC20 token on L2   |
| THRESHOLD             | 2000 UNI    | Amount required per release         |
| WITHDRAWAL_MIN_GAS    | 100,000     | Gas for L1 transfer to burn address |
| L1_RESOURCE_RECIPIENT | `0xdead`    | Final burn destination on mainnet   |

#### (Future) Hub-and-Spoke Cross-Chain

> Note: Additional cross-chain patterns are planned for future development

For non-OP Stack chains:

```
Searcher → Burn UNI (Mainnet) → Bridge Message → Release Assets (Spoke)
```

## Economic Incentives

The system relies on economic competition to ensure efficient operation:

- **Profit Motive**: Searchers compete when asset value exceeds burn costs
- **Automatic Timing**: No manual intervention required
- **Gas Optimization**: Bundled operations reduce transaction costs
- **MEV Resistance**: Fixed burn amounts prevent extraction

## Fault Tolerance (In-Progress)

Uniswap is designed to handle infrastructure failures gracefully:

- **Bridge Failures**: Each chain operates independently
- **Chain Downtime**: Fees accumulate until chain recovery
- **Oracle Failures**: Economic incentives work without price feeds

## Deployment Architecture

```
Ethereum Mainnet
├── Token Jar
├── UNI Burn Releaser (Firepit.sol)
├── V2 Fee Source (feeTo)
├── V3 Fee Source (V3FeeAdapter.sol)
```

> Crosschain system coming at a later date

## Deployed Addresses

### Ethereum Mainnet (Chain ID: 1)

| Contract           | Address                                                                                                                 |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| MainnetDeployer    | [`0xd3Aa12B99892b7D95BBAA27AEf222A8E2a038C0C`](https://etherscan.io/address/0xd3Aa12B99892b7D95BBAA27AEf222A8E2a038C0C) |
| TokenJar           | [`0xf38521f130fcCF29dB1961597bc5d2B60F995f85`](https://etherscan.io/address/0xf38521f130fcCF29dB1961597bc5d2B60F995f85) |
| Releaser (Firepit) | [`0x0D5Cd355e2aBEB8fb1552F56c965B867346d6721`](https://etherscan.io/address/0x0D5Cd355e2aBEB8fb1552F56c965B867346d6721) |
| V3FeeAdapter       | [`0x5E74C9f42EEd283bFf3744fBD1889d398d40867d`](https://etherscan.io/address/0x5E74C9f42EEd283bFf3744fBD1889d398d40867d) |
| V3OpenFeeAdapter   | [`0xf2371551Fe3937Db7c750f4DfABe5c2fFFdcBf5A`](https://etherscan.io/address/0xf2371551Fe3937Db7c750f4DfABe5c2fFFdcBf5A) |
| UNI Vesting        | [`0xCa046A83EDB78F74aE338bb5A291bF6FdAc9e1D2`](https://etherscan.io/address/0xCa046A83EDB78F74aE338bb5A291bF6FdAc9e1D2) |
| Agreement Anchor 1 | [`0xC707467e7fb43Fe7Cc55264F892Dd2D7f8Fc27C8`](https://etherscan.io/address/0xC707467e7fb43Fe7Cc55264F892Dd2D7f8Fc27C8) |
| Agreement Anchor 2 | [`0x33A56942Fe57f3697FE0fF52aB16cb0ba9b8eadd`](https://etherscan.io/address/0x33A56942Fe57f3697FE0fF52aB16cb0ba9b8eadd) |
| Agreement Anchor 3 | [`0xF9F85a17cC6De9150Cd139f64b127976a1dE91D1`](https://etherscan.io/address/0xF9F85a17cC6De9150Cd139f64b127976a1dE91D1) |

### Unichain (Chain ID: 130)

| Contract                                  | Address                                                                                                                |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| UnichainDeployer                          | [`0xD16c47bf3ae22e0B2BAc5925D990b81416f18dea`](https://uniscan.xyz/address/0xD16c47bf3ae22e0B2BAc5925D990b81416f18dea) |
| TokenJar                                  | [`0xD576BDF6b560079a4c204f7644e556DbB19140b5`](https://uniscan.xyz/address/0xD576BDF6b560079a4c204f7644e556DbB19140b5) |
| Releaser (OptimismBridgedResourceFirepit) | [`0xe0A780E9105aC10Ee304448224Eb4A2b11A77eeB`](https://uniscan.xyz/address/0xe0A780E9105aC10Ee304448224Eb4A2b11A77eeB) |

### World Chain (Chain ID: 480)

| Contract                                  | Address                                                                                                                  |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Deployer                                  | [`0x4E524DAbf30A1D6e87261c804991119181F65bb8`](https://worldscan.org/address/0x4E524DAbf30A1D6e87261c804991119181F65bb8) |
| TokenJar                                  | [`0xbDb82c2dE7D8748A3e499e771604ef8ef8544918`](https://worldscan.org/address/0xbDb82c2dE7D8748A3e499e771604ef8ef8544918) |
| Releaser (OptimismBridgedResourceFirepit) | [`0x455e844D286631566cF98D6cb2996149734618C6`](https://worldscan.org/address/0x455e844D286631566cF98D6cb2996149734618C6) |
| V3OpenFeeAdapter                          | [`0x1CE9d4DfB474Ef9ea7dc0e804a333202e40d6201`](https://worldscan.org/address/0x1CE9d4DfB474Ef9ea7dc0e804a333202e40d6201) |

### Soneium (Chain ID: 1868)

| Contract                                  | Address                                                                                                                           |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| CrossChainAccount                         | [`0x044aAF330d7fD6AE683EEc5c1C1d1fFf5196B6b7`](https://soneium.blockscout.com/address/0x044aAF330d7fD6AE683EEc5c1C1d1fFf5196B6b7) |
| Deployer                                  | [`0xD63fFE536bE3f44AE8f33C5f9c81581f9C94d1C8`](https://soneium.blockscout.com/address/0xD63fFE536bE3f44AE8f33C5f9c81581f9C94d1C8) |
| TokenJar                                  | [`0x85aeb792b94a9d79741002FC871423Ec5dAD29e9`](https://soneium.blockscout.com/address/0x85aeb792b94a9d79741002FC871423Ec5dAD29e9) |
| Releaser (OptimismBridgedResourceFirepit) | [`0xc9CC50A75cE2a5f88fa77B43e3b050480c731b6e`](https://soneium.blockscout.com/address/0xc9CC50A75cE2a5f88fa77B43e3b050480c731b6e) |
| V3OpenFeeAdapter                          | [`0x47Cf920815344Fd684A48BBEFcbfbed9C7AE09CF`](https://soneium.blockscout.com/address/0x47Cf920815344Fd684A48BBEFcbfbed9C7AE09CF) |

### Celo (Chain ID: 42220)

| Contract                                  | Address                                                                                                                |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| CrossChainAccount                         | [`0x044aAF330d7fD6AE683EEc5c1C1d1fFf5196B6b7`](https://celoscan.io/address/0x044aAF330d7fD6AE683EEc5c1C1d1fFf5196B6b7) |
| Deployer                                  | [`0x91Df768dF14E94a3fCa42badBF1907E3a3b0240f`](https://celoscan.io/address/0x91Df768dF14E94a3fCa42badBF1907E3a3b0240f) |
| TokenJar                                  | [`0x190c22c5085640D1cB60CeC88a4F736Acb59bb6B`](https://celoscan.io/address/0x190c22c5085640D1cB60CeC88a4F736Acb59bb6B) |
| Releaser (OptimismBridgedResourceFirepit) | [`0x2758FbaA228D7d3c41dD139F47dab1a27bF9bc25`](https://celoscan.io/address/0x2758FbaA228D7d3c41dD139F47dab1a27bF9bc25) |
| V3OpenFeeAdapter                          | [`0xB9952C01830306ea2fAAe1505f6539BD260Bfc48`](https://celoscan.io/address/0xB9952C01830306ea2fAAe1505f6539BD260Bfc48) |

### Zora (Chain ID: 7777777)

| Contract                                  | Address                                                                                                                         |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Deployer                                  | [`0x71F14F2A8b827cD29453498d5AF24F605caee931`](https://explorer.zora.energy/address/0x71F14F2A8b827cD29453498d5AF24F605caee931) |
| TokenJar                                  | [`0x4753C137002D802f45302b118E265c41140e73C2`](https://explorer.zora.energy/address/0x4753C137002D802f45302b118E265c41140e73C2) |
| Releaser (OptimismBridgedResourceFirepit) | [`0x2f98eD4D04e633169FbC941BFCc54E785853b143`](https://explorer.zora.energy/address/0x2f98eD4D04e633169FbC941BFCc54E785853b143) |
| V3OpenFeeAdapter                          | [`0xbfc49b47637a4DC9b7B8dE8E71BF41E519103B95`](https://explorer.zora.energy/address/0xbfc49b47637a4DC9b7B8dE8E71BF41E519103B95) |

### X Layer (Chain ID: 196)

| Contract                                  | Address                                                                                                                          |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| CrossChainAccount                         | [`0x044aAF330d7fD6AE683EEc5c1C1d1fFf5196B6b7`](https://www.oklink.com/xlayer/address/0x044aAF330d7fD6AE683EEc5c1C1d1fFf5196B6b7) |
| Deployer                                  | [`0xC943dd90D459dB082D9e9C1baBf89D4Afe79E7E0`](https://www.oklink.com/xlayer/address/0xC943dd90D459dB082D9e9C1baBf89D4Afe79E7E0) |
| TokenJar                                  | [`0x8Dd8B6D56e4a4A158EDbBfE7f2f703B8FFC1a754`](https://www.oklink.com/xlayer/address/0x8Dd8B6D56e4a4A158EDbBfE7f2f703B8FFC1a754) |
| Releaser (OptimismBridgedResourceFirepit) | [`0xe122E231cb52aea99690963Fd73E91e33E97468f`](https://www.oklink.com/xlayer/address/0xe122E231cb52aea99690963Fd73E91e33E97468f) |
| V3OpenFeeAdapter                          | [`0x6A88EF2e6511CAFfE2D006e260e7A5d1E7D4d7D7`](https://www.oklink.com/xlayer/address/0x6A88EF2e6511CAFfE2D006e260e7A5d1E7D4d7D7) |

### Arbitrum One (Chain ID: 42161)

| Contract         | Address                                                                                                                |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Deployer         | [`0x3Ac66e1bfC79032C9deFCB23aE4DEe3F8c1630eb`](https://arbiscan.io/address/0x3Ac66e1bfC79032C9deFCB23aE4DEe3F8c1630eb) |
| TokenJar         | [`0x95E337C5B155385945D407f5396387D0c2a3A263`](https://arbiscan.io/address/0x95E337C5B155385945D407f5396387D0c2a3A263) |
| Releaser         | [`0xB8018422bcE25D82E70cB98FdA96a4f502D89427`](https://arbiscan.io/address/0xB8018422bcE25D82E70cB98FdA96a4f502D89427) |
| V3OpenFeeAdapter | [`0xFF7aD5dA31fECdC678796c88B05926dB896b0699`](https://arbiscan.io/address/0xFF7aD5dA31fECdC678796c88B05926dB896b0699) |

### OP Mainnet (Chain ID: 10)

| Contract                                  | Address                                                                                                                            |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Deployer                                  | [`0x3398783D2ffE6F79B56dade84CEAea888C400da4`](https://optimistic.etherscan.io/address/0x3398783D2ffE6F79B56dade84CEAea888C400da4) |
| TokenJar                                  | [`0xb13285DF724ea75f3f1E9912010B7e491dCd5EE3`](https://optimistic.etherscan.io/address/0xb13285DF724ea75f3f1E9912010B7e491dCd5EE3) |
| Releaser (OptimismBridgedResourceFirepit) | [`0x94460443Ca27FFC1baeCa61165fde18346C91AbD`](https://optimistic.etherscan.io/address/0x94460443Ca27FFC1baeCa61165fde18346C91AbD) |
| V3OpenFeeAdapter                          | [`0xec23Cf5A1db3dcC6595385D28B2a4D9B52503Be4`](https://optimistic.etherscan.io/address/0xec23Cf5A1db3dcC6595385D28B2a4D9B52503Be4) |

### Base (Chain ID: 8453)

| Contract                                  | Address                                                                                                                 |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Deployer                                  | [`0x076f84717f3601B8Cd177bb84b217A2679B38b7d`](https://basescan.org/address/0x076f84717f3601B8Cd177bb84b217A2679B38b7d) |
| TokenJar                                  | [`0x9bD25e67bF390437C8fAF480AC735a27BcF6168c`](https://basescan.org/address/0x9bD25e67bF390437C8fAF480AC735a27BcF6168c) |
| Releaser (OptimismBridgedResourceFirepit) | [`0xFf77c0ED0B6b13A20446969107E5867abc46f53a`](https://basescan.org/address/0xFf77c0ED0B6b13A20446969107E5867abc46f53a) |
| V3OpenFeeAdapter                          | [`0xaBEA76658b205696d49B5F91b2a03536cB8A3bE1`](https://basescan.org/address/0xaBEA76658b205696d49B5F91b2a03536cB8A3bE1) |

## Development

### Prerequisites

- [Foundry](https://getfoundry.sh/) - Ethereum development toolkit
- [Node.js](https://nodejs.org/) - For additional tooling

### Installation

```bash
# Clone the repository
git clone https://github.com/Uniswap/protocol-fees
cd protocol-fees

# Install dependencies
forge install

# Build contracts
forge build
```

### Testing

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Generate coverage
forge coverage
```

### Project Structure

```
src/
├── TokenJar.sol             // General purpose contract for receiving fees
├── Deployer.sol              // A deployer contract to instantiate the initial contracts
├── base
│   ├── Nonce.sol             // Utility contract to safely sequence multiple pending transactions
│   └── ResourceManager.sol.  // Utility contract for defining the `RESOURCE` token and its amount requirements
├── feeAdapters
│   ├── V3FeeAdapter.sol   // Logic for Uniswap v3 fee-setting and collection
│   └── V4FeeAdapter.sol   // Work-in-progress logic for Uniswap v4 fee-setting and collection
├── interfaces/               // interfaces
├── libraries
│   ├── ArrayLib.sol          // Utility library
└── releasers
    ├── ExchangeReleaser.sol              // Abstract contract to exchange a RESOURCE for Token Jar assets
    ├── Firepit.sol                       // Burns UNI directly on mainnet (RESOURCE_RECIPIENT = 0xdead)
    └── OptimismBridgedResourceFirepit.sol // Two-stage burn for OP Stack L2s via bridge withdrawal

test
├── TokenJar.t.sol
├── Deployer.t.sol                        // Test Deployer configures the system properly
├── ExchangeReleaser.t.sol
├── Firepit.t.sol
├── OptimismBridgedResourceFirepit.t.sol  // Tests for L2 bridge burn mechanism
├── ProtocolFees.fork.t.sol               // Fork tests against Ethereum Mainnet, using Deployer.sol
├── V3FeeAdapter.t.sol
├── V4FeeAdapter.t.sol
├── interfaces/                           // interfaces for integrations
├── mocks/                                // mocks and examples
└── utils
    └── ProtocolFeesTestBase.sol          // Test base that configures the system
```

## Governance Proposal

For additional commentary and information please see Uniswap Governance Proposal [#92](https://vote.uniswapfoundation.org/proposals/92)

With the system already deployed, Uniswap Governance can elect into the system by executing the following calls:

| Contract         | Address                                                                                                               | Calldata                                                                     | function                               | function signature | parameters                                                                                                            |
| ---------------- | --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- | -------------------------------------- | ------------------ | --------------------------------------------------------------------------------------------------------------------- |
| UniswapV3Factory | [0x1F98431c8aD98523631AE4a59f267346ea31F984](https://etherscan.io/address/0x1f98431c8ad98523631ae4a59f267346ea31f984) | `0x13af40350000000000000000000000001a9c8182c09f50c8318d769245bea52c32be35bc` | `setOwner(address _owner)`             | `0x13af4035`       | [0xTOKENJAR](https://etherscan.io/address/0xTOKENJAR)                                                                 |
| FeeToSetter      | [0x18e433c7Bf8A2E1d0197CE5d8f9AFAda1A771360](https://etherscan.io/address/0x18e433c7Bf8A2E1d0197CE5d8f9AFAda1A771360) | `0xa2e74af60000000000000000000000001a9c8182c09f50c8318d769245bea52c32be35bc` | `setFeeToSetter(address feeToSetter_)` | `0xa2e74af6`       | [0x1a9C8182C09F50C8318d769245beA52c32BE35BC](https://etherscan.io/address/0x1a9c8182c09f50c8318d769245bea52c32be35bc) |
| UniswapV2Factory | [0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f](https://etherscan.io/address/0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f) | `0xf46901ed0000000000000000000000001a9c8182c09f50c8318d769245bea52c32be35bc` | `setFeeTo(address _feeTo)`             | `0xf46901ed`       | [0xTOKENJAR](https://etherscan.io/address/0xTOKENJAR)                                                                 |

## Security

**Audits**:
Audit reports available in [audit/](./audit/)

- OpenZeppelin
- Spearbit

## Future Development

### Protocol Fee Auctions

Advanced mechanism design for optimizing fee collection efficiency through auction-based competition.

### Additional Protocol Support

- Uniswap v4
- UniswapX fee integration
- Interface fee collection
- Third-party protocol adapters

### Cross-chain Expansion

- Additional L2 and L1 chain support
- Alternative bridge integrations
- Rollup-specific optimizations

## Contributing

1. Fork the repository
2. Create a feature branch
3. Implement changes with comprehensive tests
4. Submit a pull request

## License

This project is licensed under AGPL-3.0-only.

## Support

For questions or issues, please open an issue in the repository.
