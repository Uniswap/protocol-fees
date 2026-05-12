# V4 Custom-Accounting Fee — Design Spec

**Status:** Draft for review
**Repos affected:** `protocol-fees`, `v4-hooks-internal`
**Author:** Mark Toda + Claude
**Date:** 2026-05-11

---

## 1. Summary

Allow V4 custom-accounting hooks (aggregator hooks) to charge protocol fees in excess of the V4 `MAX_PROTOCOL_FEE = 1000` pips per-direction cap by **widening V4FeePolicy's internal fee storage from uint24 (12+12 packed) to uint48 (24+24 packed)** and moving the cap from a storage-layer property to a publication-boundary property (the manager-push call). Custom-accounting hooks read the raw uncapped value directly; the manager-push path clamps to `MAX_PROTOCOL_FEE` on its way out.

Critically: this **reuses the existing classification machinery in full** (`_resolveFamily`, `_flagRules`, `setHookFamily`, `pairFees`, `familyMultiplierPips`, `familyDefaults`, `defaultFee`). Custom-accounting hooks inherit per-pair × per-family-multiplier flexibility for free.

Concretely:
- `pairFees`, `familyDefaults`, `defaultFee` widen from `uint24` to `uint48`.
- `_validateFee` bounds each 24-bit half at `MAX_LP_FEE = 1_000_000` (was: `MAX_PROTOCOL_FEE = 1000`).
- `_applyMultiplier` and `_encodeFee`/`_decodeFee` widen accordingly.
- `computeFee` returns `uint48` (raw, uncapped).
- `V4FeeAdapter._setProtocolFee` clamps each direction to `MAX_PROTOCOL_FEE` and packs to `uint24` (12+12) for the manager. Custom-accounting hooks short-circuit to 0.
- `V4FeeAdapter.getFee` keeps its `uint24` return type by performing the clamp-and-pack internally (backwards-compatible for off-chain consumers).
- Custom-accounting hooks read the existing public `V4FeeAdapter.getFeeRaw(PoolKey) → uint48` directly for their per-direction fee — no new adapter view needed.
- `v4-hooks-internal/ProtocolFees.sol::_getProtocolFee` unpacks the uint48 by direction.

---

## 2. Background

### 2.1 How fees flow today (aggregator pool)

For a V4 pool whose hook has any `RETURNS_DELTA` permission bit set (i.e. a custom-accounting hook — bits 0–3 of the address):

```
governance ─► V4FeePolicy.computeFee  ──packed uint24 12+12, ≤ MAX_PROTOCOL_FEE──►  V4FeeAdapter.getFee
                                                                                         │
                                                                       V4FeeAdapter.triggerFeeUpdate
                                                                                         │
                                                                                         ▼
                                                                     PoolManager.setProtocolFee(key, fee24)
                                                                                         │
                                                                                         ▼
                                                                                   Slot0.protocolFee
                                                                                         │
                                                                                         ▼
hook.beforeSwap ─► external swap ─► poolManager.getSlot0(id).protocolFee ─► poolManager.take(curr, tokenJar, amt)
```

The hook is *already* taking the fee itself via `poolManager.take` (`v4-hooks-internal/src/aggregator-hooks/ProtocolFees.sol:62`). The PoolManager isn't charging the fee — it just publishes the rate via Slot0.

### 2.2 Where the 0.1% cap comes from — and why 12+12 isn't a hard blocker

Two reinforcing constraints in v4-core:

1. **Manager-side validation.** `PoolManager.setProtocolFee` reverts with `ProtocolFeeTooLarge` if any 12-bit component of the packed `uint24` exceeds `ProtocolFeeLibrary.MAX_PROTOCOL_FEE = 1000` (0.1% per direction).
2. **Packed-representation ceiling.** Slot0 carries protocol fee as `uint24 = (fee1to0 << 12) | fee0to1`. Each 12-bit component holds 0..4095.

Both constraints apply only to the **`setProtocolFee` call boundary**. Our internal storage doesn't have to match. We widen storage to uint48 (24+24) and do the clamp-and-pack inside `V4FeeAdapter._setProtocolFee`. No gas penalty — uint48 fits in the same 32-byte slot; bit operations are still 256-bit native EVM ops.

### 2.3 Custom-accounting detection is already structural

`V4FeePolicy._isCustomAccounting(address)` (line 310) is a pure address bitmask:

```solidity
uint160 public constant CUSTOM_ACCOUNTING_MASK = 0xF;
function _isCustomAccounting(address hook) internal pure returns (bool) {
    return uint160(hook) & CUSTOM_ACCOUNTING_MASK != 0;
}
```

### 2.4 Existing classification machinery (the thing we reuse)

`V4FeePolicy` already has the full plumbing for hook classification:

- `_flagRules: FlagRule[]` (line 90) — governance-configured `(requiredFlags, familyId)` walked in order, first-match-wins. Setter at line 190.
- `hookFamilyId: mapping(address => uint8)` (line 69) — per-address governance override, set via `setHookFamily`.
- `IFeeClassifiedHook.protocolFeeFlags() → uint256` — optional hook self-report (`HookFeeFlags.AGGREGATOR`, etc.).
- `_resolveFamily(address) → uint8` (line 321) — governance override → flag-rule walk → familyId or 0.
- `pairFees: mapping(bytes32 => uint24)`, `familyDefaults: mapping(uint8 => uint24)`, `familyMultiplierPips`, `defaultFee` — all the configuration knobs.

The Classified branch of `computeFee` (line 127–138) already combines them as `pairFee × familyMultiplier` → `familyDefault` → `defaultFee`. This is exactly the resolution shape custom-accounting hooks want — they just need it to return uncapped values.

After widening, all of this resolution machinery is *reused* for custom-accounting fees without modification.

---

## 3. Problem

Aggregator hooks need to charge fees in ranges that exceed `MAX_PROTOCOL_FEE = 1000 pips` (0.1% per direction):
- Stable/stable: ~1–5 bps (fits, but tight)
- Non-stable: 5–50 bps (does not fit)

The fee mechanism inside V4 (Slot0 → swap accrual → `collectProtocolFees`) is irrelevant — the hook takes the fee itself via `poolManager.take`. The only thing tying us to the manager-side cap is that the hook reads the *rate* from Slot0, and Slot0 was set via `setProtocolFee` which validates against `MAX_PROTOCOL_FEE`.

---

## 4. Goals & Non-Goals

### Goals

- Custom-accounting hooks can charge fees up to `MAX_LP_FEE = 1_000_000` pips (100%) per direction.
- **Full reuse of existing Classified resolution** — pair × family multiplier, family defaults, global default — for custom-accounting hooks.
- Backwards-compatible adapter `getFee` return type (`uint24`, manager-compatible packed).
- Aggregator hook code is minimally changed in its swap logic — only the rate-lookup function and one new param.
- Forward-compatible with future asymmetric per-direction fees (packed 24+24 preserves that capability).

### Non-goals

- Per-pool overrides for custom-accounting fees (the existing `V4FeeAdapter.poolOverrides` stays packed/capped and unused on this path).
- Changing how non-custom-accounting hooks (dynamic-fee LP-style, StaticNativeMath) settle fees against the manager.
- Aggregator hooks implementing `IFeeClassifiedHook` in v1. Governance can use `setHookFamily(addr, familyId)` per address; auto-classification via `protocolFeeFlags()` is a follow-up.

---

## 5. Design

### 5.1 Storage widening

```solidity
// V4FeePolicy
mapping(bytes32 pairHash => uint48) public pairFees;         // was: uint24
mapping(uint8 familyId => uint48) public familyDefaults;     // was: uint24
uint48 public defaultFee;                                    // was: uint24
mapping(uint8 familyId => uint24) public familyMultiplierPips;  // unchanged
```

Each `uint48` is packed `(fee1to0 << 24) | fee0to1` — same shape as today's uint24 but with 24-bit halves instead of 12-bit. Each 24-bit half holds 0..16_777_215, ample headroom over `MAX_LP_FEE = 1_000_000`.

Sentinel value: `ZERO_FEE_SENTINEL = type(uint48).max` (was `type(uint24).max`).

Storage cost: identical. mappings consume one 32-byte slot per entry regardless of value width as long as the value fits in 256 bits. Gas: identical (SLOAD is 32 bytes either way; bit ops are 256-bit native).

### 5.2 Validation widens

```solidity
function _validateFee(uint48 feeValue) internal pure {
    uint256 fee0 = feeValue & 0xFFFFFF;
    uint256 fee1 = feeValue >> 24;
    if (fee0 > LPFeeLibrary.MAX_LP_FEE || fee1 > LPFeeLibrary.MAX_LP_FEE) revert InvalidFeeValue();
}
```

(Was: `ProtocolFeeLibrary.isValidProtocolFee(uint24)`.) `MAX_LP_FEE = 1_000_000` is the natural structural ceiling (100% per direction).

**Bucket `alphaPips` stays bounded by `MAX_PROTOCOL_FEE`** — the StaticNativeMath path only fires for non-custom-accounting hooks, whose fees always flow through the manager-push path that needs ≤ MAX_PROTOCOL_FEE. No reason to widen there.

### 5.3 `_applyMultiplier` widens

```solidity
function _applyMultiplier(uint48 baseFee, uint24 multiplierPips) internal pure returns (uint48) {
    uint256 fee0 = uint256(baseFee & 0xFFFFFF) * multiplierPips / MULTIPLIER_DENOMINATOR;
    uint256 fee1 = uint256(baseFee >> 24) * multiplierPips / MULTIPLIER_DENOMINATOR;
    return uint48((fee1 << 24) | fee0);
}
```

Overflow analysis: `MAX_LP_FEE × MULTIPLIER_DENOMINATOR = 10^12`, fits in uint40, safe in uint256.

### 5.4 `computeFee` returns uint48 (raw, uncapped)

```solidity
function computeFee(PoolKey calldata key) external view returns (uint48 feePacked) {
    // ... unchanged StaticNativeMath path returns uint48 (still ≤ MAX_PROTOCOL_FEE per
    //     direction because buckets are bounded) ...
    // ... unchanged Classified path returns uint48 (each direction ≤ MAX_LP_FEE) ...
}
```

Body shape stays identical — only return type widens and the values it returns can now exceed `MAX_PROTOCOL_FEE` for the Classified path.

### 5.5 `V4FeeAdapter._setProtocolFee` — clamp at the manager boundary

```solidity
uint160 internal constant CUSTOM_ACCOUNTING_MASK = 0xF;

function _setProtocolFee(PoolKey memory key) internal {
    PoolId id = key.toId();
    (uint160 sqrtPriceX96,,,) = POOL_MANAGER.getSlot0(id);
    if (sqrtPriceX96 == 0) return;

    bool isCustomAccounting = uint160(address(key.hooks)) & CUSTOM_ACCOUNTING_MASK != 0;
    uint24 feeValue;
    if (isCustomAccounting) {
        // Hook reads directly via getFeeRaw; Slot0 unused for these pools.
        // Push 0 for deterministic off-chain state. Also bypasses pool-override.
        feeValue = 0;
    } else {
        // Clamp each direction to MAX_PROTOCOL_FEE and pack as 12+12 for V4
        feeValue = _clampAndPackForManager(getFeeRaw(key));
    }
    POOL_MANAGER.setProtocolFee(key, feeValue);
    emit FeeUpdateTriggered(msg.sender, id, feeValue);
}
```

`getFeeRaw` resolves the uint48 raw value via the existing override → policy waterfall:

```solidity
function getFeeRaw(PoolKey memory key) public view returns (uint48) {
    uint48 stored = poolOverrides[key.toId()];
    if (stored != 0) return _decodeFee(stored);
    if (address(policy) == address(0)) return 0;
    return policy.computeFee(key);
}
```

The `poolOverrides` mapping itself widens from `uint24` to `uint48` — same widening pattern as policy state, same setter validation cap.

### 5.6 `V4FeeAdapter.getFee` keeps `uint24` for back-compat

```solidity
function getFee(PoolKey memory key) public view returns (uint24) {
    return _clampAndPackForManager(getFeeRaw(key));
}

function _clampAndPackForManager(uint48 raw) internal pure returns (uint24) {
    uint256 fee0 = uint256(raw & 0xFFFFFF);
    uint256 fee1 = uint256(raw >> 24);
    if (fee0 > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) fee0 = ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
    if (fee1 > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) fee1 = ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
    return uint24((fee1 << 12) | fee0);
}
```

Off-chain consumers reading `adapter.getFee(key)` continue to receive a manager-compatible packed uint24 — same shape as today.

### 5.7 Custom-accounting hooks read `getFeeRaw` directly

The adapter does not expose a separate `getCustomAccountingFee` view. Custom-accounting hooks read the existing public `getFeeRaw(PoolKey) → uint48` at swap time and unpack the appropriate direction:

```solidity
// V4FeeAdapter (unchanged from §5.4)
function getFeeRaw(PoolKey memory key) public view returns (uint48) {
    uint48 stored = poolOverrides[key.toId()];
    if (stored != 0) return _decodeFee(stored);
    if (address(policy) == address(0)) return 0;
    return policy.computeFee(key);
}
```

A dedicated wrapper that gated on `_isCustomAccounting(hook)` would be structurally redundant: aggregator hooks identify themselves by their own address bits and cannot accidentally not be custom-accounting. The manager-push short-circuit in `_setProtocolFee` (§5.5) still uses the `CUSTOM_ACCOUNTING_MASK` constant to push 0 to Slot0 for these pools; the hook-side path simply reads the raw fee.

### 5.8 Hook-side change

Modify `v4-hooks-internal/src/aggregator-hooks/ProtocolFees.sol::_getProtocolFee` to call the adapter and unpack by direction:

```solidity
function _getProtocolFee(IPoolManager poolManager, bool zeroForOne, PoolId, PoolKey memory key)
    internal view returns (uint24 protocolFee)
{
    address controller = poolManager.protocolFeeController();
    if (controller == address(0) || controller.code.length == 0) {
        return _getProtocolFeeFromSlot0(poolManager, key.toId(), zeroForOne);
    }
    try IV4FeeAdapter(controller).getFeeRaw(key) returns (uint48 packed) {
        return uint24(zeroForOne ? packed & 0xFFFFFF : packed >> 24);
    } catch {
        return _getProtocolFeeFromSlot0(poolManager, key.toId(), zeroForOne);
    }
}
```

`_getProtocolFeeFromSlot0` is the current Slot0-reading implementation, kept as fallback.

### 5.9 Governance UX (example)

```solidity
// Once: classify hooks
policy.setFlagRules([
    FlagRule({requiredFlags: HookFeeFlags.AGGREGATOR | HookFeeFlags.STABLE_PAIR, familyId: 1}),
    FlagRule({requiredFlags: HookFeeFlags.AGGREGATOR,                            familyId: 2}),
]);

// Or per-address override (no IFeeClassifiedHook dependency on the hook)
policy.setHookFamily(fluidLiteHook, 2);

// Configure resolution
policy.setFamilyMultiplier(2, 1_000_000);              // 100% pass-through for family 2
policy.setPairFee(usdc, weth, _symmetric(50_000));     // 5% on USDC/WETH
policy.setPairFee(usdc, usdt, _symmetric(5));          // 0.5 bps on USDC/USDT for stable family
policy.setFamilyMultiplier(1, 1_000_000);              // 100% pass-through for family 1
policy.setFamilyDefault(2, _symmetric(50_000));        // fallback for family 2 on unconfigured pairs
policy.setFamilyDefault(1, _symmetric(5));             // fallback for family 1
```

Where `_symmetric(v)` is a helper that builds `(v << 24) | v`.

Hook resolution at swap time:
1. `_isCustomAccounting(hook)` — pure bitmask, no SLOAD (lives on the hook side; the adapter no longer re-gates).
2. `getFeeRaw → policy.computeFee → _resolveFamily + pair/family math`.
3. Hook unpacks the appropriate direction.

---

## 6. API Reference

### 6.1 Changes (breaking)

#### `IV4FeePolicy`

```solidity
// Return type changes uint24 → uint48
function pairFees(bytes32 pairHash) external view returns (uint48);
function familyDefaults(uint8 familyId) external view returns (uint48);
function defaultFee() external view returns (uint48);
function computeFee(PoolKey calldata key) external view returns (uint48 feePacked);

// Param type changes uint24 → uint48
function setPairFee(Currency currency0, Currency currency1, uint48 feeValue) external;
function setFamilyDefault(uint8 familyId, uint48 feeValue) external;
function setDefaultFee(uint48 feeValue) external;
```

Events `PairFeeUpdated`, `FamilyDefaultUpdated`, `DefaultFeeUpdated` widen their `feeValue` field to `uint48`.

`ZERO_FEE_SENTINEL` widens to `type(uint48).max`.

#### `IV4FeeAdapter`

```solidity
// Return type changes uint24 → uint48
function poolOverrides(PoolId poolId) external view returns (uint48);

// Param type changes uint24 → uint48
function setPoolOverride(PoolId poolId, uint48 feeValue) external;
```

Event `PoolOverrideUpdated` widens `feeValue` to `uint48`.

### 6.2 Additions

#### `IV4FeeAdapter`

```solidity
/// @notice Resolves the raw protocol fee for a pool, in uint48 (24+24) — not
/// clamped for the manager. Custom-accounting hooks (those with any
/// RETURNS_DELTA permission bit set in their address) read this view at swap
/// time and unpack the per-direction pips value. Non-custom-accounting
/// consumers should use `getFee` instead, which clamps each direction to
/// MAX_PROTOCOL_FEE and packs as 12+12 for PoolManager.setProtocolFee.
function getFeeRaw(PoolKey memory key) external view returns (uint48);
```

No dedicated `getCustomAccountingFee` wrapper: gating the raw view on hook address bits would be structurally redundant (aggregator hooks identify themselves by their own address). The `CUSTOM_ACCOUNTING_MASK` constant remains internal to the adapter and is used only by `_setProtocolFee` to short-circuit the manager push to 0 for these pools.

### 6.3 Preserved (backwards-compatible)

- `V4FeeAdapter.getFee(PoolKey) → uint24` — unchanged shape, still manager-compatible packed 12+12. Internally clamps from the uint48 raw value.
- `V4FeeAdapter._setProtocolFee` push to `PoolManager.setProtocolFee(key, uint24)` — unchanged interface to v4-core.
- The entire Classified resolution semantics — no new branches, no new gates.

---

## 7. Deployment & Migration

### 7.1 Deployment order

1. Deploy new `V4FeePolicy` with widened types.
2. Deploy new `V4FeeAdapter` with widened types + clamp-on-push + new views.
3. `PoolManager.setProtocolFeeController(newAdapter)`.
4. Wire policy/feeSetter on the new contracts.
5. Configure resolution — `setFlagRules` or `setHookFamily`, `setPairFee`, `setFamilyMultiplier`, etc.
6. Permissionless `batchTriggerFeeUpdate` clears Slot0.protocolFee to 0 on custom-accounting pools.

### 7.2 Hook upgrade (separate timeline)

The `v4-hooks-internal` change is deploy-independent thanks to the try/catch fallback. Hooks compiled against the new `ProtocolFees.sol` fall back to Slot0 if the adapter doesn't expose `getFeeRaw` yet (e.g. against the pre-widening adapter).

### 7.3 v4-hooks-internal pinned `protocol-fees`

Bump the pinned submodule commit. Update `MockV4FeeAdapter` to match the new interface (widened types + new views).

---

## 8. Test Plan

### 8.1 `protocol-fees` repo

**Migration of existing tests:** all existing assertions on packed fee values (`(N << 12) | N`) change to `(N << 24) | N`. Existing test scaffolding (`FEE_100 = ...`) updates accordingly. No semantic changes to existing tests — they continue to assert the same behaviors against the manager-push path.

**New unit cases (V4FeePolicy):**

- `_validateFee` accepts values up to `MAX_LP_FEE` per direction; reverts at `MAX_LP_FEE + 1`.
- `_applyMultiplier` round-trip: `pairFee × multiplier / 1e6` matches direct computation for boundary inputs (1, MAX_LP_FEE).
- `computeFee` for a Classified-path custom-accounting hook returns an uncapped uint48 that decodes to the configured `pairFee × familyMultiplier`.
- `computeFee` for a StaticNativeMath pool stays bounded by `MAX_PROTOCOL_FEE` (buckets unchanged).
- Pair fee setters / family default setter / default fee setter all accept widened values.
- Fuzz: arbitrary uint48 values within bound pass setters and round-trip through getters.

**New unit cases (V4FeeAdapter):**

- `getFeeRaw` returns the uncapped uint48 value from policy, regardless of hook type (no address-bit gate on the raw view).
- `getFee` clamps each direction to `MAX_PROTOCOL_FEE` and packs as 12+12, regardless of raw value size. Specifically: set a pair fee of `(50_000 << 24) | 50_000`, `getFeeRaw` returns it unchanged, `getFee` returns `(1000 << 12) | 1000`.
- `triggerFeeUpdate` for custom-accounting hook pushes 0 to Slot0 (regardless of raw fee value).
- `triggerFeeUpdate` for non-custom-accounting hook pushes the clamped+packed value (e.g. raw `(50_000, 50_000)` → manager receives `(1000 << 12) | 1000`).
- `batchTriggerFeeUpdate` mixed batch behaves per-key correctly.
- `setPoolOverride` accepts widened values up to `MAX_LP_FEE` per direction.

**Fork (real PoolManager):**

- Initialize a pool with a custom-accounting hook (etched `BaseTestHooks` at `0x88`). Use `setHookFamily(hookAddr, 1) + setFamilyMultiplier(1, 1_000_000) + setPairFee(c0, c1, _symmetric(50_000))`. Assert:
  - `adapter.getFeeRaw(key)` decodes to (50_000, 50_000) — the value the hook reads at swap time.
  - `adapter.getFee(key)` returns `(1000 << 12) | 1000` (clamped).
  - `triggerFeeUpdate(key)` → `Slot0.protocolFee == 0`.
  - Re-trigger keeps the state stable.
  - Pool override bypass holds.

### 8.2 `v4-hooks-internal` repo

Same scope as before. Mock adapter exposes `setMockCustomAccountingFee(uint48 packed)` (widened). Tests cover:
- Exact-in zeroForOne with fee 5_000, 100_000, 1_000_000 (per direction).
- Asymmetric fee: `(50_000 << 24) | 10_000` — assert hook charges 10_000 zeroForOne and 50_000 oneForZero.
- 0-fee no-op.
- Adapter revert → fallback to Slot0.
- `protocolFeeController() == address(0)` → fallback.

---

## 9. Risks & Open Questions

### 9.1 Risks

**R1 — Interface break on `computeFee`, `pairFees`, `familyDefaults`, `defaultFee`, `poolOverrides`.**
Direct callers of `V4FeePolicy` and `V4FeeAdapter` see return type widening from `uint24` to `uint48`. Off-chain tools that ABI-decode these will need updating. Mitigation: `V4FeeAdapter.getFee` retains its `uint24` shape, which is the most-consumed external surface; direct policy/adapter state-getter callers are a smaller surface.

**R2 — Cross-coupling: shared family across custom-accounting and non-custom-accounting hooks.**
If governance assigns the same family ID to a custom-accounting hook *and* a non-custom-accounting Classified hook (dynamic-fee), the SAME `pairFees[ph] × familyMultiplier[family]` value feeds both consumption paths. Custom-accounting reads it raw; non-custom-accounting gets clamped on manager push. Could surprise an operator. Mitigation: governance discipline + clearly documented behavior + tests that demonstrate the clamp.

**R3 — Stale Slot0 during partial rollout.**
Hooks still on the old `ProtocolFees.sol` code read Slot0 (now forced to 0). They'd charge 0 fee. Mitigation: stage the adapter swap chain-by-chain, or land the hook-side change first (try/catch makes it forward-safe).

**R4 — Test churn.**
Every existing test that uses `FEE_X = (X << 12) | X` packing needs updating to `(X << 24) | X`. Mechanical but voluminous (~30–50 touchpoints in the existing 114 tests).

**R5 — Audit story for the bypass + clamp.**
Auditors verify: (a) custom-accounting hooks always read the uncapped path; (b) non-custom-accounting hooks always clamp to MAX_PROTOCOL_FEE on push; (c) the address-bit check matches V4's permission encoding. Tests cover each.

### 9.2 Open questions

**Q1 — Asymmetric fees: useful or YAGNI?**
The 24+24 packed shape preserves asymmetric per-direction fees, but the spec assumes governance sets symmetric values via a helper. If asymmetric is never used, the packed format adds complexity for no benefit. Keeping for now (matches the existing 12+12 shape and is easy to support).

**Q2 — Should the adapter gate the raw read on `_isCustomAccounting`?**
Resolved: no. An earlier draft added a `getCustomAccountingFee(PoolKey)` wrapper that short-circuited to 0 for non-custom-accounting hooks. The gate is structurally redundant — aggregator hooks identify themselves by their own address bits and cannot accidentally not be custom-accounting. The adapter exposes the public `getFeeRaw` view; the hook-side `_isCustomAccounting` check (a pure bitmask, no SLOAD) is the only gate that's actually load-bearing. `CUSTOM_ACCOUNTING_MASK` stays on the adapter for `_setProtocolFee`'s Slot0 short-circuit.

---

## 10. Alternatives Considered

### A1 — Per-pair-hash storage with parallel mapping

**Rejected.** Built a parallel classification system orthogonal to the existing `_resolveFamily` machinery. No reuse of `familyMultiplier` or `familyDefaults`. Earlier draft.

### A2 — Single new per-family uncapped mapping (`customAccountingFamilyFee`)

**Rejected.** Doesn't give per-pair granularity within a family. Would require governance to choose either "one rate per family" or "one family per pair" — both worse than the natural pair × family resolution that already exists in the Classified path. Earlier draft.

### A3 — Relax `_validateFee` to MAX_LP_FEE but keep uint24 packed (12+12)

**Rejected.** uint24 packed 12+12 holds each direction in only 12 bits = 0..4095 pips. Even removing the validation cap, 4095 is the structural ceiling. Insufficient for the 50_000+ pip target.

### A4 — Switch internal storage to unpacked symmetric uint24

**Rejected.** Drops the existing asymmetric-fee capability without a use-case-driven reason. The 24+24 widening preserves it.

### A5 — Hook-pushed model (adapter writes to hook storage)

**Rejected.** Requires every aggregator hook to implement a setter, cross-contract storage-consistency reasoning. Pull is simpler.

---

## 11. Acknowledgments

This spec is the product of multiple iterations. The first draft proposed per-pair-hash storage; the second per-family flat. The final shape — widening internal storage rather than adding parallel storage — came from the observation that the 12+12 packed representation is *only* required at V4's `setProtocolFee` boundary, not in our internal state. Once that constraint moved from "storage layer" to "publication boundary," the natural design fell out: keep the full Classified hierarchy, widen the values, clamp at the manager wall.
