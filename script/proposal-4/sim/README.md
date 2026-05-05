# Simulation

To simulate execution of this proposal, run the following from shell terminals.

TODO:

- clean this
- add a way to exclude tests unless this flow is running (or pin block number)
- add impersonation so the following dont fail:
  - `ActivateL2Proposals` needs someone with historical uni votes
  - `SimulateExecution` on BNB Chain needs the `Constants.BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER`
  - `SimulateExecution` on Celo needs the `Constants.Celo.UNISWAP_WORMHOLE_MESSAGE_RECEIVER`
  - `SimulateExecution` on Polygon needs the `Constants.Polygon.ETHEREUM_PROXY`

remove `__` from test functions in `test/end-to-end/proposal-4/` first

```sh
# --------------------------------------------------------------------------------------------------
# -- setup

# terminal 0:
source .env && anvil --rpc-url $MAINNET_RPC_URL --port $FORK_MAINNET_PORT

# terminal 1:
source .env && anvil --rpc-url $CELO_RPC_URL --port $FORK_CELO_PORT

# terminal 2:
source .env && anvil --rpc-url $BNB_CHAIN_RPC_URL --port $FORK_BNB_CHAIN_PORT

# terminal 3:
source .env && anvil --rpc-url $POLYGON_RPC_URL --port $FORK_POLYGON_PORT

# terminal 4:
source .env

 export TEST_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

export TEST_ADDR=$(cast wallet address --private-key $PK)

export BALANCE_HEX=$(cast to-hex $(cast to-wei 1000))

cast rpc anvil_setBalance $TEST_ADDR $BALANCE_HEX --rpc-url $FORK_MAINNET_RPC_URL
cast rpc anvil_setBalance $TEST_ADDR $BALANCE_HEX --rpc-url $FORK_CELO_RPC_URL
cast rpc anvil_setBalance $TEST_ADDR $BALANCE_HEX --rpc-url $FORK_BNB_CHAIN_RPC_URL
cast rpc anvil_setBalance $TEST_ADDR $BALANCE_HEX --rpc-url $FORK_POLYGON_RPC_URL

# --------------------------------------------------------------------------------------------------
# -- preflight checks

forge test --match-contract PreflightCheckTest

# --------------------------------------------------------------------------------------------------
# -- script runs

forge script script/proposal-4/deploys/DeployWormholeInfraBNBChain.s.sol:DeployWormholeInfraBNBChainScript --rpc-url $FORK_BNB_CHAIN_RPC_URL --private-key=$PK --broadcast

forge script script/proposal-4/deploys/DeployWormholeInfraPolygon.s.sol:DeployWormholeInfraPolygonScript --rpc-url $FORK_POLYGON_RPC_URL --private-key=$PK --broadcast

forge script script/proposal-4/deploys/DeployWormholeInfraEthereum.s.sol:DeployWormholeInfraEthereumScript --rpc-url $FORK_MAINNET_RPC_URL --private-key=$PK --broadcast

forge script script/proposal-4/deploys/ConfigWormholeInfraBNBChain.s.sol:ConfigWormholeInfraBNBChainScript  --rpc-url $FORK_BNB_CHAIN_RPC_URL --private-key=$PK --broadcast

forge script script/proposal-4/deploys/ConfigWormholeInfraPolygon.s.sol:ConfigWormholeInfraPolygonScript --rpc-url $FORK_POLYGON_RPC_URL --private-key=$PK --broadcast

forge script script/proposal-4/deploys/ConfigWormholeInfraEthereum.s.sol:ConfigWormholeInfraEthereumScript  --rpc-url $FORK_MAINNET_RPC_URL --private-key=$PK --broadcast

forge script script/proposal-4/deploys/DeployAndConfigureFeeInfraBNBChain.s.sol:DeployAndConfigureFeeInfraBNBChainScript  --rpc-url $FORK_BNB_CHAIN_RPC_URL --private-key=$PK --broadcast

forge script script/proposal-4/deploys/DeployAndConfigureFeeInfraPolygon.s.sol:DeployAndConfigureFeeInfraPolygonScript  --rpc-url $FORK_POLYGON_RPC_URL --private-key=$PK --broadcast

forge script script/proposal-4/ActivateL2sProposal.s.sol:ActivateL2Proposals  --rpc-url $FORK_MAINNET_RPC_URL --private-key=$PK --broadcast

forge script script/proposal-4/sim/SimulateExecution.s.sol:SimulateExecutionScript --rpc-url $FORK_BNB_CHAIN_RPC_URL

forge script script/proposal-4/sim/SimulateExecution.s.sol:SimulateExecutionScript --rpc-url $FORK_CELO_RPC_URL

forge script script/proposal-4/sim/SimulateExecution.s.sol:SimulateExecutionScript --rpc-url $FORK_POLYOGN_RPC_URL

# --------------------------------------------------------------------------------------------------
# -- postflight checks

forge test test/end-to-end/proposal-4/PostflightChecks.t.sol
```
