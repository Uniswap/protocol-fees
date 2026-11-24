# Proposal 105

Turns on v4 protocol fees on five chains, Celo, Soneium, X Layer, World Chain and Zora. Also lowers the `optimalFeeE6` on Arbitrum's two StablePairHook USDG/USDC pools. It implements the temp check [Protocol Fee Expansion: v4 on Five More Chains](https://gov.uniswap.org/t/temp-check-protocol-fee-expansion-v4-on-five-more-chains/26349).

Actions 00 to 04 each set one chain's PoolManager `protocolFeeController` to a new `V4FeeAdapter`, sent through the chain's L1CrossDomainMessenger and run by the chain's CrossChainAccount, which owns the PoolManager. The bulk of the changes are configured when deploying and configuring the new adapter, policy and ruleset contracts, which is done via the prereq scripts. Those actions "merely" wire up each new adapter to its chain's PoolManager.

Action 05 sends a retryable ticket through Arbitrum's Inbox that updates the StablePairHook's fee configs.

The policy, its rulesets and the parameter format are proposal 104's. [Proposal 104's index](../proposal-104/Index.md) explains how the policy sets a pool's fee and what each ruleset charges.

## Parameters

[`params/v4-fee-policy.json`](./params/v4-fee-policy.json) holds each chain's parameters, in the format the header of [proposal 104's `PolicyParams.sol`](../proposal-104/params/PolicyParams.sol) defines.

- Every chain uses the fee levels set by proposal 104's existing policy: `volatilePairFee` 1000 and `stablePairFee` 300.
- None of the five chains has an aggregator hook, so no hook is assigned the aggregator ruleset.
- Celo's currency IDs are from the existing `V4FeePolicy`, which proposal 6 deployed but never connected to the PoolManager. The other four chains don't have any.
- X Layer's StablePairHook proxy is assigned the stable pair ruleset, and its liquidity-launcher hooks are assigned the static curve ruleset.

Each new adapter sends fees to the chain's TokenJar. `tokenJar()` in [`params/Constants.sol`](./params/Constants.sol) returns the TokenJar only if the chain's `V3OpenFeeAdapter` sends its fees to the same one, so v3 and v4 fees on a chain reach the same TokenJar.

## The Arbitrum StablePairHook update

The StablePairHook proxy on Arbitrum, `StableHook.PROXY` in [`params/StableHook.sol`](./params/StableHook.sol), sets each pool's LP fee from a per-pool fee config. Action 05 calls its `batchUpdateFeeConfig` for the USDG/USDC pools with tick spacing 1 and 2, setting each pool's `optimalFeeE6` to `StableHook.NEW_OPTIMAL_FEE_E6`. The hook replaces a pool's whole fee config, so the update carries the other three fields, `k`, `targetMultiplier` and `referenceSqrtPriceX96`, at their current values. The ticket runs from the Timelock's alias, which holds the hook's `CONFIG_MANAGER_ROLE`. [`StableHookUpdate.sol`](./StableHookUpdate.sol) builds the call and holds the checks before and after it.

## What changes for existing pools

Each fixture in [`test/end-to-end/proposal-105/fixtures/`](../../test/end-to-end/proposal-105/fixtures/) gives every listed pool's `before` fee, the fee the PoolManager stores, and its `expected` fee after the new adapter is set by the proposal. None of the pools on these chains currently has a v4 protocol fee. After the proposal, hookless pools and pools with X Layer's liquidity-launcher hooks pay the hookless curve's fee, pools with X Layer's StablePairHook pay the stable pair ruleset's fee, and pools with any other hook stay at 0.

## Prerequisite: deploy the adapters and policies

Run [`prereq/DeployV4FeeAdapter.s.sol`](./prereq/DeployV4FeeAdapter.s.sol) once on each of the five chains. Anyone can run it, and the deployer holds no authority once it finishes.

```shell
forge script script/proposal-105/prereq/DeployV4FeeAdapter.s.sol --rpc-url <chain> --broadcast
```

The script extends proposal 104's prerequisite script. On each chain it:

1. Deploys and assigns the policy and rulesets exactly as proposal 104's does, and hands the policy to the CrossChainAccount.
2. Deploys a `V4FeeAdapter` for the chain's PoolManager and TokenJar, and sets its policy.
3. Hands the adapter to the CrossChainAccount: `setFeeSetter`, then `transferOwnership`.
4. Asserts the result with `checkNewPolicy` and `checkNewAdapter`, then records the six addresses in `.records/Proposal105.json`.

To check a recorded deployment against the live chain afterwards:

```shell
forge script script/proposal-105/prereq/DeployV4FeeAdapter.s.sol --sig "check()" --rpc-url <chain>
```

## Check and write the proposal

`preflight()` checks Ethereum, all five chains and Arbitrum in one run, each at its latest block. It needs every chain's RPC URL in `.env`, and reverts if an RPC alias reaches another chain.

```shell
forge script script/proposal-105/Proposal105.s.sol --sig "preflight()"
```

- `preflightEthereum()` asserts that each chain's L1CrossDomainMessenger is unpaused and that its portal serves the chain's ID, and that Arbitrum's Inbox is unpaused and serves Arbitrum.
- `preflightRemote()` asserts, on each of the five chains, that the CrossChainAccount runs only the Timelock's messages from that messenger, that it owns the PoolManager, that the PoolManager has no fee controller, and that the recorded adapter and policy pass `checkNewAdapter` and `checkNewPolicy`. World Chain's and Zora's CrossChainAccounts are an older version with no getters, so the check reads their storage.
- On Arbitrum, `preflightRemote()` asserts that the Timelock's alias holds the StablePairHook's `CONFIG_MANAGER_ROLE`, that each pool's fee config is the one the update replaces, and that Arbitrum's base fee is under the retryable ticket's gas bid.

To check one chain at a pinned block, run `preflightRemote(uint256)` against it with `--fork-block-number`.

`run()` runs `preflightEthereum()` and writes the proposal to `out/.seatbelt/Proposal105.json` for Governance Seatbelt:

```shell
forge script script/proposal-105/Proposal105.s.sol --rpc-url mainnet
```

## Governance actions

Actions 00 to 04 are each one `sendMessage` call on the chain's L1CrossDomainMessenger, with no value. The message tells the chain's CrossChainAccount to call `setProtocolFeeController` on the PoolManager with the recorded adapter. Action 05 is one retryable ticket through Arbitrum's Inbox. `buildProposal` builds them in this order:


| Action | Chain       | Route                  | Runs as                   | Value       |
| ------ | ----------- | ---------------------- | ------------------------- | ----------- |
| 00     | Celo        | L1CrossDomainMessenger | CrossChainAccount         | 0           |
| 01     | Soneium     | L1CrossDomainMessenger | CrossChainAccount         | 0           |
| 02     | X Layer     | L1CrossDomainMessenger | CrossChainAccount         | 0           |
| 03     | World Chain | L1CrossDomainMessenger | CrossChainAccount         | 0           |
| 04     | Zora        | L1CrossDomainMessenger | CrossChainAccount         | 0           |
| 05     | Arbitrum    | Inbox retryable ticket | Timelock's Arbitrum alias | 0.01002 ETH |


Action 05's ticket pays a 200,000 gas limit at 0.1 gwei plus 0.01 ETH of submission cost, from govkit's `InboxEncoder`. GovernorBravo's `execute` pays each action's value from the Governor's balance, so attach any shortfall to `execute`.

## After execution

- The OP Stack bridges relay actions 00 to 04 without further steps.
- Arbitrum redeems action 05's ticket when it arrives. If Arbitrum's base fee is above the ticket's gas bid at that moment, Arbitrum does not redeem it, and someone must call `redeem` on ArbRetryableTx with the ticket's ID within seven days.
- After each message runs, `postflightRemote()` against its chain asserts the PoolManager's fee controller is the recorded adapter, or on Arbitrum that each pool's fee config carries the new `optimalFeeE6`. Once every message has run, `postflight()` checks all five chains and Arbitrum in one run:
  ```shell
  forge script script/proposal-105/Proposal105.s.sol --sig "postflight()"
  ```
- Pools pay their new fee once someone calls `batchTriggerFeeUpdate` on the chain's adapter with their keys.

## Tests

The fork tests in [`test/end-to-end/proposal-105/`](../../test/end-to-end/proposal-105/) run the real scripts at pinned blocks:

- `Proposal105EthereumForkTest`: `test_preflightEthereum` runs the Ethereum preflight, and `test_execute` executes the whole proposal as the Timelock with stand-in adapters and asserts that each messenger sends one message and Arbitrum's Inbox one ticket.
- `Proposal105ArbitrumForkTest`: `test_preflightRemote` runs `preflightRemote()` on Arbitrum, and `test_execute` asserts that action 05's Inbox serves Arbitrum, runs its ticket from the Timelock's alias within the ticket's gas limit, then runs `postflightRemote()`. `forge test` sets the base fee of a fork to 0, so the base fee check runs only against the live chain.
- One `Proposal105<Chain>ForkTest` per chain, at its fixture's block:
  - `test_feesBefore` asserts that each fixture pool's `before` is the fee the PoolManager stores for it.
  - `test_preflightRemote` runs the prerequisite script, then `preflightRemote()`.
  - `test_execute` runs the prerequisite script, replays the deposit the chain's action creates through the chain's messenger and CrossChainAccount, runs `postflightRemote()`, then asserts each fixture pool's `expected` fee through `getFee` and, after `batchTriggerFeeUpdate`, in the PoolManager.

`StableHookUpdateTest`, a unit test without a fork, asserts action 05's ticket: its Inbox and Timelock, its gas limit and fees, its 0.01002 ETH value, and its exact call on Arbitrum.

Each fixture lists every pool with a hook the policy assigns a ruleset to, one hookless pool for each LP fee, and a sample of other hooked pools. The `before` fees come from the chain. The `expected` fees come from a model of the rulesets kept separate from the contracts, applied to the parameter file, so the tests show the contracts charge what that model charges; they do not show the parameter file is right.

```shell
forge test --match-path 'test/end-to-end/proposal-105/*'
```
