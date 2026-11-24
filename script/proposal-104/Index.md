# Proposal 104

Replaces the v1 `V4FeePolicy` on the existing `V4FeeAdapter` on eight chains (Ethereum, Arbitrum, Base, OP Mainnet, BNB Chain, Polygon, Robinhood Chain and Arc) with a policy built on rulesets. It implements the temp check [Upgrade the v4 Protocol Fee System](https://gov.uniswap.org/t/temp-check-upgrade-the-v4-protocol-fee-system/26348).

Each action is one `setPolicy` call on one chain's adapter, sent through that chain's governance route. The bulk of the changes are configured when deploying and configuring the new policy and ruleset contracts, which is done via the prereq scripts. The proposal "merely" wires up the new policy contract to the adapter. Proposal 105 deploys the same policy on five more chains; see [its index](../proposal-105/Index.md).

## How the new policy sets a pool's fee

`V4FeePolicy.computeFee` resolves a pool's protocol fee in this order:

1. If the pool's hook address has a ruleset, the ruleset sets the fee. Hookless pools use address zero, which has the static curve ruleset.
2. A hooked pool with a static LP fee and no custom accounting uses the ruleset at `NATIVE_MATH_POOL_SENTINEL`. This proposal sets none there.
3. A hook that declares `IV4ProtocolFeeRuleset` through ERC165 sets its own fee. Later hooks can opt in this way without a policy change. For example, aggregator hooks can opt in by forwarding to the ruleset at `AGGREGATOR_HOOK_RULESET_KEY`.
4. Any other pool pays `defaultFee`, which is 0.

Each chain's policy uses four rulesets:


| Ruleset                     | Charges                                                                                                                                                                                           |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `V4StaticCurveRuleset`      | The hookless fee curve that proposal 6 set: eight buckets on the pool's LP fee, from `hooklessFeeBuckets()` in [`params/Constants.sol`](./params/Constants.sol).                                  |
| `V4AggregatorHookRuleset`   | `stablePairFee` when both currencies have the same currency ID, otherwise `volatilePairFee`, divided by the hook's `protocolFeeMultiplier`. It reverts when the multiplier is 0 or above the fee. |
| `V4StablePairHookRuleset`   | A fee computed from the StablePairHook's `feeConfig` for the pool.                                                                                                                                |
| `V4VolatilePairHookRuleset` | A fee computed from the VolatilePairHook's `feeConfig` for the pool.                                                                                                                              |


## Parameters

[`params/v4-fee-policy.json`](./params/v4-fee-policy.json) holds each chain's fee levels, currency IDs and the hooks assigned to each ruleset, in named groups. The header of [`params/PolicyParams.sol`](./params/PolicyParams.sol) defines the file's layout and what each group holds. The prerequisite script and the preflight read the file through `loadPolicyParams`, which refuses a missing or misplaced key and a fee that does not fit in `uint24`.

- The fee levels stay at the levels set by the existing policy: `volatilePairFee` 1000 and `stablePairFee` 300, except on Base, which keeps 300 and 100.
- Aggregator hooks that opted into a fee through `protocolFeeFlags()` but are not Uniswap Labs hooks keep their fee: they are in the `thirdParty` group. These include Pons on Robinhood Chain and other teams' hooks such as Aerodrome, WOOFi and Flash V2.
- Some hooks are not assigned any ruleset but are listed in `excludedAggregatorHooks` for documentation purposes:
  - versions Uniswap Labs no longer routes to: those with `protocolFeeMultiplier` 10, and those with no `protocolFeeMultiplier` getter;
  - other hooks with no `protocolFeeMultiplier` getter, for which the aggregator ruleset would revert and so break any `batchTriggerFeeUpdate` that includes their pools;
  - hooks whose `protocolFeeFlags()` is not 2048.
- The `LitePSMAggregator` hooks don't have a fee and are not listed in this file. Neither are the LBP and CCA hooks that Uniswap Labs marked for exclusion.
- The StablePairHook proxy `0xd5711b1f57e75b1c91c32ad96c4d4e5019d6bcc0` on Robinhood Chain is not listed either. It runs StablePairHook code, but nobody knows who deployed it, and its roles are held by the account that deployed it, so whoever that is could change its pools' fee without governance.
- Later per-launch `InitializerHook`s are expected to opt in through ERC165, so they don't need to be listed in this file.

## What changes for existing pools

Each fixture in [`test/end-to-end/proposal-104/fixtures/`](../../test/end-to-end/proposal-104/fixtures/) gives every listed pool's `before` policy fee, and its `expected` fee after the new policy is set by the proposal. These are the kinds of change, in pips per direction:


| Change                                                                            | Before            | After                    |
| --------------------------------------------------------------------------------- | ----------------- | ------------------------ |
| Aggregator pools whose currencies now share a currency ID, such as two ETH tokens | 40, or 12 on Base | 12, or 4 on Base         |
| Pools with StablePairHook and VolatilePairHook proxies                            | 0                 | The pair ruleset's fee   |
| Pools with liquidity-launcher hooks the v1 policy did not assign                  | 0                 | The hookless curve's fee |


The table leaves out some pools  with aggregator hooks that are in the excluded group in the `v4-fee-policy.json`. Their nominal fee drops to 0, but, since they are old Uniswap Labs hooks that have either expired are no longer routed to, that means there is effectively no change.

Every other pool's fee is unchanged:


| Pools with unchanged fees                                                               | Fee (pips per direction) |
| --------------------------------------------------------------------------------------- | ------------------------ |
| Aggregator pools with Uniswap Labs-deployed hooks whose pair class is the same as in v1 | 40, 12 or 4              |
| Hookless pools                                                                          | The hookless curve's fee |
| Pools with hooks the policy does not assign, including the `LitePSMAggregator` hooks    | 0                        |
| Pools with third-party aggregator hooks                                                 | 40, 12 or 4              |
| Pools with hooks whose `protocolFeeFlags()` is not 2048                                 | 0                        |
| Pools with hooks in the v1 native-math family                                           | The hookless curve's fee |


## Prerequisite: deploy the policies

Run [`prereq/DeployV4FeePolicy.s.sol`](./prereq/DeployV4FeePolicy.s.sol) once on each of the eight chains. Anyone can run it, and the deployer holds no authority once it finishes.

```shell
forge script script/proposal-104/prereq/DeployV4FeePolicy.s.sol --rpc-url <chain> --broadcast
```

On each chain the script:

1. Deploys the four rulesets, then the policy, with the deployer as owner and fee setter.
2. Assigns the static curve ruleset to hookless pools and to the static curve hooks, the aggregator ruleset to the aggregator hooks and to `AGGREGATOR_HOOK_RULESET_KEY`, and each pair ruleset to its hooks. It sends the assignments in batches of 400, which keeps each transaction under Ethereum's per-transaction gas cap of 16,777,216 (EIP-7825) with forge's 30% gas buffer.
3. Hands the policy to the chain's governance executor: `setFeeSetter`, then `transferOwnership`.
4. Asserts the result with `checkNewPolicy`, then records the five addresses in `.records/Proposal104.json`.

The script refuses to run on a chain that already has a recorded policy. To check a recorded deployment against the live chain afterwards:

```shell
forge script script/proposal-104/prereq/DeployV4FeePolicy.s.sol --sig "check()" --rpc-url <chain>
```

## Check and write the proposal

`preflight()` checks Ethereum and all eight chains in one run, each at its latest block. It needs every chain's RPC URL in `.env`, and reverts if an RPC alias reaches another chain.

```shell
forge script script/proposal-104/Proposal104.s.sol --sig "preflight()"
```

- `preflightEthereum()` asserts that each route delivers to its chain: each Inbox serves its rollup's chain ID, each OP Stack messenger's portal serves its chain ID, the Wormhole sender is owned by the Timelock, and FxRoot sends to the FxChild that Polygon's `EthereumProxy` accepts.
- `preflightRemote()` asserts, on each chain, that the adapter is the PoolManager's fee controller, the governance executor owns it, it still uses the v1 policy, the route runs the Timelock's messages as the executor, and the recorded policy passes `checkNewPolicy`. On Arbitrum and Robinhood Chain it also asserts that the chain's base fee is under the retryable ticket's gas bid.

To check one chain at a pinned block, run `preflightRemote(uint256)` against it with `--fork-block-number`.

`run()` runs `preflightEthereum()` and writes the proposal to `out/.seatbelt/Proposal104.json` for Governance Seatbelt:

```shell
forge script script/proposal-104/Proposal104.s.sol --rpc-url mainnet
```

## Governance actions

Each action sets one chain's adapter policy to the recorded policy. `buildProposal` builds them in this order:


| Action | Chain           | Route                  | Runs as                        | Value                |
| ------ | --------------- | ---------------------- | ------------------------------ | -------------------- |
| 00     | Ethereum        | Direct call            | Timelock                       | 0                    |
| 01     | Arbitrum        | Inbox retryable ticket | Timelock's Arbitrum alias      | 0.01002 ETH          |
| 02     | Base            | L1CrossDomainMessenger | CrossChainAccount              | 0                    |
| 03     | OP Mainnet      | L1CrossDomainMessenger | CrossChainAccount              | 0                    |
| 04     | BNB Chain       | Wormhole               | UniswapWormholeMessageReceiver | Wormhole message fee |
| 05     | Polygon         | FxRoot                 | EthereumProxy                  | 0                    |
| 06     | Robinhood Chain | Inbox retryable ticket | Timelock's Arbitrum alias      | 0.01002 ETH          |
| 07     | Arc             | Wormhole               | UniswapWormholeMessageReceiver | Wormhole message fee |


Each retryable ticket pays a 200,000 gas limit at 0.1 gwei plus 0.01 ETH of submission cost, from govkit's `InboxEncoder`. `buildProposal` reads the Wormhole message fee from the Wormhole core when it builds the proposal; if the fee changes before execution, execution reverts and the proposal must be made again. GovernorBravo's `execute` pays each action's value from the Governor's balance, so attach any shortfall to `execute`.

## After execution

- Actions 00, 02, 03 and 05 run on their chains without further steps.
- Wormhole does not deliver actions 04 and 07. Someone must fetch each message's VAA from Wormhole's API and call `receiveMessage` on the chain's receiver, as proposals 4 and 7 did.
- If Arbitrum's or Robinhood Chain's base fee is above the ticket's gas bid when action 01 or 06 arrives, the chain does not redeem the ticket. Someone must call `redeem` on ArbRetryableTx with the ticket's ID within seven days.
- After each message runs, `postflightRemote()` against its chain asserts the adapter uses the recorded policy. Once every message has run, `postflight()` checks all eight chains in one run:
  ```shell
  forge script script/proposal-104/Proposal104.s.sol --sig "postflight()"
  ```
- Pools pay their new fee once someone calls `batchTriggerFeeUpdate` with their keys.

## Tests

The fork tests in [`test/end-to-end/proposal-104/`](../../test/end-to-end/proposal-104/) run the real scripts at pinned blocks:

- `Proposal104EthereumForkTest`: `test_preflightEthereum` runs the Ethereum preflight, and `test_execute` executes the whole proposal as the Timelock with stand-in policies and asserts that each route sends one message.
- One `Proposal104<Chain>ForkTest` per chain, at its fixture's block:
  - `test_feesBefore` asserts that each fixture pool's `before` is the fee the v1 adapter sets for it, so the fixture matches the chain.
  - `test_preflightRemote` runs the prerequisite script, then `preflightRemote()`.
  - `test_execute` runs the prerequisite script and the chain's action as the chain delivers it, runs `postflightRemote()`, then asserts each fixture pool's `expected` fee through `getFee` and, after `batchTriggerFeeUpdate`, in the PoolManager. Ethereum, Arbitrum and Robinhood Chain run the decoded call as the executor, with the route's gas limit on Arbitrum and Robinhood Chain. Base and OP Mainnet replay the deposit the action creates. Polygon replays the state sync through FxChild. BNB Chain and Arc run the call in the payload the Wormhole sender publishes.

Each fixture lists every pool with a hook the policy assigns a ruleset to, up to 20 pools with each excluded hook, one hookless pool for each LP fee, and a sample of other hooked pools. The `before` fees come from the chain. The changed `expected` fees come from a model of the rulesets kept separate from the contracts, applied to the parameter file, so the tests show the contracts charge what that model charges; they do not show the parameter file is right.

```shell
forge test --match-path 'test/end-to-end/proposal-104/*'
```