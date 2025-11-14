# Uniswap Fee Collection

*A unified system for collecting and converting fees from arbitrary revenue sources on arbitrary chains.*

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
3. UNI tokens are burned, reducing total supply
4. Searcher profits from asset value exceeding UNI burn cost

#### (In-Progress) Cross-Chain UNI Burn

> Note: Cross-chain value accrual is not ready at this time, below we outline our expectations

For chains without native UNI:

```
Searcher → Burn UNI (Mainnet) → Bridge Message → Release Assets (Spoke)
```

**Mechanism:**

1. Searcher burns UNI on Ethereum mainnet
2. Cross-chain message triggers asset release on spoke chain
3. Monotonic nonce ensures strict ordering
4. Bundled multicalls optimize gas efficiency

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
    ├── ExchangeReleaser.sol  // Utility contract to exchange a RESOURCE for Token Jar assets
    └── Firepit.sol           // Burns UNI (resource) in exchange for Token Jar assets

test
├── TokenJar.t.sol
├── Deployer.t.sol            // Test Deployer configures the system properly
├── ExchangeReleaser.t.sol
├── Firepit.t.sol
├── ProtocolFees.fork.t.sol   // Fork tests against Ethereum Mainnet, using Deployer.sol
├── V3FeeAdapter.t.sol
├── V4FeeAdapter.t.sol
├── interfaces/               // interfaces for integrations
├── mocks/                    // mocks and examples
└── utils
    └── ProtocolFeesTestBase.sol   // Test base that configures the system
```

## Governance Proposal

For additional commentary and information please see Uniswap Governance Proposal [#92](https://www.tally.xyz/gov/uniswap/proposal/91)

With the system already deployed, Uniswap Governance can elect into the system by executing the following calls:

| Contract         | Address                                                                                                               | Calldata                                                                     | function                               | function signature | parameters                                                                                                            |
|------------------|-----------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------|----------------------------------------|--------------------|-----------------------------------------------------------------------------------------------------------------------|
| UniswapV3Factory | [0x1F98431c8aD98523631AE4a59f267346ea31F984](https://etherscan.io/address/0x1f98431c8ad98523631ae4a59f267346ea31f984) | `0x13af40350000000000000000000000001a9c8182c09f50c8318d769245bea52c32be35bc` | `setOwner(address _owner)`             | `0x13af4035`       | [0xTOKENJAR](https://etherscan.io/address/0xTOKENJAR)                                                               |
| FeeToSetter      | [0x18e433c7Bf8A2E1d0197CE5d8f9AFAda1A771360](https://etherscan.io/address/0x18e433c7Bf8A2E1d0197CE5d8f9AFAda1A771360) | `0xa2e74af60000000000000000000000001a9c8182c09f50c8318d769245bea52c32be35bc` | `setFeeToSetter(address feeToSetter_)` | `0xa2e74af6`       | [0x1a9C8182C09F50C8318d769245beA52c32BE35BC](https://etherscan.io/address/0x1a9c8182c09f50c8318d769245bea52c32be35bc) |
| UniswapV2Factory | [0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f](https://etherscan.io/address/0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f) | `0xf46901ed0000000000000000000000001a9c8182c09f50c8318d769245bea52c32be35bc` | `setFeeTo(address _feeTo)`             | `0xf46901ed`       | [0xTOKENJAR](https://etherscan.io/address/0xTOKENJAR)                                                               |

## Security

- **Economic Security**: Competitive incentives prevent manipulation
- **Comprehensive Testing**: 156 tests with fuzz testing, fork testing, and extensive edge cases
- **Audits**: Two rounds of audits from OpenZeppelin, with reports in [audit/](./audit/)

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

