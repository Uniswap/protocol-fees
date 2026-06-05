# V4 Fee Policy — Governance Operator Guide

This guide helps **fee setters** choose the right knob for a fee outcome on Uniswap V4. It reflects the unified `V4FeePolicy` resolution model (`NATIVE_MATH_FAMILY_ID = 255`, `UNCLASSIFIED_FAMILY_ID = 0`).

**Contracts**


| Contract       | Role                                                                                           |
| -------------- | ---------------------------------------------------------------------------------------------- |
| `V4FeeAdapter` | `protocolFeeController` on the PoolManager; per-pool overrides; `triggerFeeUpdate` / `collect` |
| `V4FeePolicy`  | Replaceable fee logic; families, buckets, pair/family defaults                                 |


**Roles**


| Role                           | Can do                                             |
| ------------------------------ | -------------------------------------------------- |
| `feeSetter` (adapter + policy) | All fee configuration below                        |
| `owner` (adapter + policy)     | Set `feeSetter`, swap `V4FeePolicy` on the adapter |


---

## End-to-end fee waterfall

Every pool’s protocol fee is resolved in this order:

```
1. adapter.poolOverrides[poolId]     → if set, use this (always wins)
2. policy.computeFee(poolKey)       → see below
3. adapter returns 0                → if policy address is unset
```

Inside `**policy.computeFee**`:

```
1. family := _resolveFamily(poolKey)

2. if family == 0 (unclassified)
      → defaultFee

3. if pairClassFees[pair][family] is set
      → that fee (including explicit zero)

4. if family == 255 (native math)
      → fee buckets from key.fee (piecewise linear)

5. if familyDefaults[family] is set
      → family default

6. → defaultFee
```

---

## How `family` is chosen (`_resolveFamily`)


| Step | Source                                                               | Result                                         |
| ---- | -------------------------------------------------------------------- | ---------------------------------------------- |
| 1    | `hookFamilyId[hook] != 0`                                            | Use governance assignment (families **1–255**) |
| 2    | Static pool: no return-delta hook bits **and** `key.fee != 0x800000` | **255** (native math)                          |
| 3    | `hook.protocolFeeFlags()` + `flagRules` (first match)                | Rule’s `familyId`                              |
| 4    | Else                                                                 | **0** (unclassified)                           |


**Static pool** = hook address has none of v4’s `*_RETURNS_DELTA` permission bits (low bits 0–3) and LP fee is not the dynamic-fee marker `0x800000`.

**Custom-accounting hook** = any return-delta bit set in the hook address (baked in at deploy). These pools never auto-resolve to native math unless you assign a family in step 1.

**Dynamic-fee pool** = `key.fee == 0x800000`. Live LP fee can change every swap; buckets are not used. Assign a family or rely on unclassified + `defaultFee`.

Check onchain: `policy.isCustomAccounting(hook)` and `LPFeeLibrary.isDynamicFee(key.fee)`.

---

## Pool types at a glance


| Pool shape                                       | Default `family`               | Fee mechanics                                 |
| ------------------------------------------------ | ------------------------------ | --------------------------------------------- |
| Vanilla (`hooks = 0`, static LP fee)             | **255**                        | `pairClassFees[pair][255]` or **fee buckets** |
| Static hook (e.g. `beforeSwap` only, static fee) | **255** unless `setHookFamily` | Same as vanilla                               |
| Custom-accounting or dynamic-fee, no assignment  | **0**                          | `**defaultFee` only**                         |
| Any pool with `setHookFamily(hook, F)`           | **F**                          | Classified waterfall (steps 3–6 above)        |


---

## Use case → best mechanism


| Goal                                                                  | Use                                                                                                  | Contract         | Notes                                                                                                                          |
| --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| **Protocol fee scales with LP fee tier** (0.05% / 0.3% / 1% pools)    | `setFeeBuckets`                                                                                      | Policy           | Default for vanilla + static-hook pools (`family` 255). Max 16 buckets, ascending `lpFeeFloor`.                                |
| **Different fee for one token pair** (all vanilla pools on that pair) | `setPairClassFee(c0, c1, 255, fee)`                                                                  | Policy           | `255` = `NATIVE_MATH_FAMILY_ID`. Overrides buckets for that pair only.                                                         |
| **Force one pool’s fee** (promo, migration, emergency)                | `setPoolOverride(poolId, fee)`                                                                       | Adapter          | Highest priority; ignores policy. Use `0` for explicit zero.                                                                   |
| **Zero fee on one pool**                                              | `setPoolOverride(poolId, 0)`                                                                         | Adapter          | Simplest per-pool exempt.                                                                                                      |
| **Flat fee for all pools on one hook**                                | `setHookFamily(hook, F)` + `setFamilyDefault(F, fee)`                                                | Policy           | Works for **static hooks** (opt out of buckets) and classified hooks. Use governance family **1–254** (`setFamilyDefault` rejects 255). |
| **Zero fee for all pools on one hook**                                | `setHookFamily(hook, F)` + `setFamilyDefault(F, 0)`                                                  | Policy           | `0` encodes as explicit-zero sentinel.                                                                                         |
| **Zero fee for one pair on a hook family**                            | `setPairClassFee(c0, c1, F, 0)`                                                                      | Policy           | Does not fall through to family default.                                                                                       |
| **Per-pair fee within a hook family**                                 | `setPairClassFee(c0, c1, F, fee)`                                                                    | Policy           | Finer than family default.                                                                                                     |
| **Auto-group hooks by behavior**                                      | `setFlagRules` + `setFamilyDefault` per family                                                       | Policy           | Hook must implement `IFeeClassifiedHook.protocolFeeFlags()`. Rules sorted most-specific first (higher popcount). Max 32 rules. |
| **Override auto-classification for one hook**                         | `setHookFamily(hook, F)`                                                                             | Policy           | Beats flag rules. `setHookFamily(hook, 0)` clears assignment.                                                                  |
| **Default for unclassified hooks / dynamic pools**                    | `setDefaultFee`                                                                                      | Policy           | Used when `family == 0`.                                                                                                       |
| **Remove a configured fee**                                           | `clearFeeBuckets`, `clearFamilyDefault`, `clearPairClassFee`, `clearDefaultFee`, `clearPoolOverride` | Policy / Adapter | Prefer `clear`* over writing zero to “unset” bucket/default slots.                                                             |
| **Apply new policy logic chain-wide**                                 | Deploy policy → `adapter.setPolicy` → `triggerFeeUpdate` / `batchTriggerFeeUpdate`                   | Adapter          | PoolManager keeps old fee until retriggered.                                                                                   |


---

## Mechanism reference

### Adapter (`V4FeeAdapter`)


| Function                       | Purpose                                           |
| ------------------------------ | ------------------------------------------------- |
| `setPoolOverride(poolId, fee)` | Per-pool fee; wins over everything                |
| `clearPoolOverride(poolId)`    | Remove override                                   |
| `triggerFeeUpdate(key)`        | Push resolved fee to PoolManager (permissionless) |
| `batchTriggerFeeUpdate(keys)`  | Batch retrigger                                   |
| `collect(...)`                 | Pull accrued fees to TokenJar (permissionless)    |


### Policy — native math (family 255)


| Function                            | Purpose                                                                                           |
| ----------------------------------- | ------------------------------------------------------------------------------------------------- |
| `setFeeBuckets(buckets)`            | Global schedule: `alpha + beta × (lpFee - floor) / 1_000_000` per direction, clamped to 1000 pips |
| `clearFeeBuckets()`                 | Remove schedule (native math returns 0 if no pair override)                                       |
| `setPairClassFee(c0, c1, 255, fee)` | Pair-specific override on native path                                                             |


Bucket tips:

- `beta = 0` → flat `alpha` per tier.
- `alpha = 0` → pure multiplier on LP fee.
- Lowest bucket’s `alpha` is the floor when `lpFee < floor_0`.

### Policy — classified families (1–255)


| Function                                 | Purpose                                                   |
| ---------------------------------------- | --------------------------------------------------------- |
| `setHookFamily(hook, familyId)`          | Manual family; `0` = clear                                |
| `batchSetHookFamily(assignments)`        | Batch version                                             |
| `setFamilyDefault(familyId, fee)`        | Default for governance families **1–254** (rejects 0 and 255) |
| `setPairClassFee(c0, c1, familyId, fee)` | Pair + family slot                                        |
| `setFlagRules(rules)`                    | Map `protocolFeeFlags()` → family                         |
| `clearFlagRules()`                       | Remove all rules                                          |
| `setDefaultFee(fee)`                     | Unclassified + final fallback                             |


### Policy — constants (read-only)


| Constant                   | Value | Meaning                                       |
| -------------------------- | ----- | --------------------------------------------- |
| `NATIVE_MATH_FAMILY_ID()`  | `255` | Native math + `pairClassFees[pair][255]` slot |
| `UNCLASSIFIED_FAMILY_ID()` | `0`   | No family; `defaultFee` only                  |


---

## Flag rules

Hooks that implement `protocolFeeFlags()` return an opaque `uint256` bitfield. The policy
ascribes **no** meaning to any individual bit — per rule, it only checks that all of a
rule's `requiredFlags` bits are set in the hook's returned value. The meaning of each bit
is a convention agreed between governance (which writes the rules) and hooks (which set the
bits); it is **not** enumerated onchain.

```solidity
// bit 11 (1 << 11) is the aggregator convention — see the table below
FlagRule({ requiredFlags: 1 << 11, familyId: 3 })
```

- `requiredFlags` must be non-zero; all listed bits must be set on the hook's report.
- `familyId` must be **> 0** in rules (use family 3, not 0).
- Order rules from **most specific** to **least** (decreasing popcount of `requiredFlags`).

Flag rules do **not** affect `family` by themselves — only the combination of `flagRules`
and the hook's returned bits does.

### Bit conventions in active use

| Bit       | Value  | Convention      | Notes                                              |
| --------- | ------ | --------------- | -------------------------------------------------- |
| `1 << 11` | `2048` | Aggregator hook | Only convention currently relied on in production. |

Bits not listed here have no agreed meaning. Before publishing a rule against a new bit,
add it to this table so hook authors and governance share one source of truth.

---

## Recipes (copy-paste patterns)

### A. Turn on tiered fees for all vanilla pools

```text
setFeeBuckets([...])          // policy
batchTriggerFeeUpdate(keys)   // adapter — all target pools
```

### B. WETH/USDC pair pays 5 bps protocol fee everywhere (vanilla pools)

```text
setPairClassFee(WETH, USDC, 255, fee)   // sorted: currency0 < currency1
triggerFeeUpdate(...)                   // per pool or batch
```

### C. Partner static-hook: flat 3 bps on all their pools

```text
setHookFamily(hook, 7)
setFamilyDefault(7, fee_300)
batchTriggerFeeUpdate(partnerPoolKeys)
```

### D. Exempt partner static-hook entirely

```text
setHookFamily(hook, 7)
setFamilyDefault(7, 0)        // explicit zero
batchTriggerFeeUpdate(...)
```

### E. Custom-accounting hook: classify via flags

```text
setFlagRules([{ STABLE_PAIR, 4 }, { AGGREGATOR, 5 }, ...])
setFamilyDefault(4, fee_stable)
setFamilyDefault(5, fee_agg)
// hooks with protocolFeeFlags() pick up families automatically
```

### F. One pool only: zero fee (e.g. launch pool)

```text
setPoolOverride(poolId, 0)      // adapter — no policy family needed
triggerFeeUpdate(key)
```

### G. Dynamic-fee pool with governance family

```text
setHookFamily(hook, 2)          // or address(0) if no hook
setFamilyDefault(2, fee)
// optional: setPairClassFee for specific pairs
triggerFeeUpdate(key)
```

---

## Footguns

1. **Config ≠ live fee** — Changing policy or overrides does not update PoolManager until `triggerFeeUpdate` (anyone can call).
2. **Family 255 and `familyDefaults`** — Native math uses buckets and `pairClassFees[pair][255]`. `setFamilyDefault(255, …)` and `clearFamilyDefault(255)` **revert** (`InvalidFamilyId`). `setHookFamily(hook, 255)` is still allowed to force the native-math branch on classified pools.
3. **Unclassified ≠ native math** — `family == 0` uses only `defaultFee`. It never reads fee buckets, even if buckets are configured.
4. **Explicit zero vs unset** — `setFamilyDefault(F, 0)` and `setPairClassFee(..., 0)` mean **zero fee**. To remove config, use `clearFamilyDefault` / `clearPairClassFee`.
5. **Pair ordering** — `setPairClassFee` requires `currency0 < currency1` (sorted addresses).
6. **Dynamic LP fee** — Do not rely on `key.fee` for amount on dynamic pools; assign a family and use family/pair defaults.
7. **Return-delta hooks** — Address bits 0–3 force classified path unless you `setHookFamily`. `beforeSwap`-only hooks (bit 7, etc.) stay on native math by default.
8. **Policy swap** — `adapter.setPolicy(newPolicy)` requires retrigger on all pools; consider batch.

---

## Quick decision tree

```text
Need to set fee for ONE pool only?
  YES → adapter.setPoolOverride
  NO ↓

Pool vanilla (no hook / static hook, static LP fee)?
  YES → fee buckets and/or pairClassFees[..., 255]
  NO ↓

Know the hook address and want same fee on all its pools?
  YES → setHookFamily + setFamilyDefault (or pairClassFees)
  NO ↓

Want hooks to self-select by behavior?
  YES → setFlagRules + setFamilyDefaults
  NO ↓

Fallback for odd hooks / dynamic fee / no rules match?
  → setDefaultFee
```

---

## Related code

- `src/feeAdapters/V4FeePolicy.sol` — `computeFee`, `_resolveFamily`
- `src/feeAdapters/V4FeeAdapter.sol` — `getFee`, overrides
- `src/interfaces/IFeeClassifiedHook.sol` — hook self-report interface
- `test/V4FeeAdapter.t.sol` — unit tests (search `Unified resolution regression`)

