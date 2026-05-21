# Simulation

To simulate execution of this proposal, run the following from shell terminals.

## Terminal 0

Mainnet fork maps `MAINNET_RPC_URL` to `FORK_MAINNET_RPC_URL` on `FORK_MAINNET_PORT`.

```sh
source .env && anvil --rpc-url $MAINNET_RPC_URL --port $FORK_MAINNET_PORT
```

## Terminal 1

Mainnet fork maps `CELO_RPC_URL` to `FORK_CELO_RPC_URL` on `FORK_CELO_PORT`.

```sh
source .env && anvil --rpc-url $CELO_RPC_URL --port $FORK_CELO_PORT
```

## Terminal 2

Mainnet fork maps `BNB_CHAIN_RPC_URL` to `FORK_BNB_CHAIN_RPC_URL` on `FORK_BNB_CHAIN_PORT`.

```sh
source .env && anvil --rpc-url $BNB_CHAIN_RPC_URL --port $FORK_BNB_CHAIN_PORT
```

## Terminal 3

Mainnet fork maps `POLYGON_RPC_URL` to `FORK_POLYGON_RPC_URL` on `FORK_POLYGON_PORT`.

```sh
source .env && anvil --rpc-url $POLYGON_RPC_URL --port $FORK_POLYGON_PORT
```

## Terminal 4

Runs:

- Test account & balance initialization
- Preflight check tests
- Scripts:
  - Deploy Wormhole to BNBChain
  - Deploy Wormhole to Polygon
  - Deploy Wormhole to Ethereum
  - Configure Wormhole on BNBChain
  - Configure Wormhole on Polygon
  - Configure Wormhole on Ethereum
  - Deploy and Configure Fee Infra on BNBChain
  - Deploy and Configure Fee Infra on Polygon
- Postflight check tests
  - Includes a mock run of the proposal

```sh
# --------------------------------------------------------------------------------------------------
# -- ACCOUNT INITIALIZATION
#
source .env

export TEST_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

export TEST_ADDR=$(cast wallet address --private-key $TEST_PK);

export BALANCE_HEX=$(cast to-hex $(cast to-wei 1000));

cast rpc anvil_setBalance $TEST_ADDR $BALANCE_HEX --rpc-url $FORK_MAINNET_RPC_URL;
cast rpc anvil_setBalance $TEST_ADDR $BALANCE_HEX --rpc-url $FORK_CELO_RPC_URL;
cast rpc anvil_setBalance $TEST_ADDR $BALANCE_HEX --rpc-url $FORK_BNB_CHAIN_RPC_URL;
cast rpc anvil_setBalance $TEST_ADDR $BALANCE_HEX --rpc-url $FORK_POLYGON_RPC_URL;

# --------------------------------------------------------------------------------------------------
# -- PREFLIGHT CHECK TESTS
#
PROP4_PREFLIGHT=true forge test --match-contract PreflightCheckTest

# --------------------------------------------------------------------------------------------------
# -- SCRIPTS
#
forge script script/proposal-4/deploys/DeployWormholeInfraBNBChain.s.sol:DeployWormholeInfraBNBChainScript --rpc-url $FORK_BNB_CHAIN_RPC_URL --private-key=$TEST_PK --broadcast

forge script script/proposal-4/deploys/DeployWormholeInfraPolygon.s.sol:DeployWormholeInfraPolygonScript --rpc-url $FORK_POLYGON_RPC_URL --private-key=$TEST_PK --broadcast

forge script script/proposal-4/deploys/DeployWormholeInfraEthereum.s.sol:DeployWormholeInfraEthereumScript --rpc-url $FORK_MAINNET_RPC_URL --private-key=$TEST_PK --broadcast

forge script script/proposal-4/deploys/ConfigWormholeInfraBNBChain.s.sol:ConfigWormholeInfraBNBChainScript  --rpc-url $FORK_BNB_CHAIN_RPC_URL --private-key=$TEST_PK --broadcast

forge script script/proposal-4/deploys/ConfigWormholeInfraPolygon.s.sol:ConfigWormholeInfraPolygonScript --rpc-url $FORK_POLYGON_RPC_URL --private-key=$TEST_PK --broadcast

forge script script/proposal-4/deploys/ConfigWormholeInfraEthereum.s.sol:ConfigWormholeInfraEthereumScript  --rpc-url $FORK_MAINNET_RPC_URL --private-key=$TEST_PK --broadcast

forge script script/proposal-4/deploys/DeployAndConfigureFeeInfraBNBChain.s.sol:DeployAndConfigureFeeInfraBNBChainScript  --rpc-url $FORK_BNB_CHAIN_RPC_URL --private-key=$TEST_PK --broadcast

forge script script/proposal-4/deploys/DeployAndConfigureFeeInfraPolygon.s.sol:DeployAndConfigureFeeInfraPolygonScript  --rpc-url $FORK_POLYGON_RPC_URL --private-key=$TEST_PK --broadcast

# --------------------------------------------------------------------------------------------------
# -- POSTFLIGHT CHECK TESTS
#
PROP4_POSTFLIGHT=true forge test test/end-to-end/proposal-4/PostflightChecks.t.sol
```
