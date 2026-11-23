// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {BaseTestHooks} from "v4-core/test/BaseTestHooks.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";

import {V4FeeAdapter, IV4FeeAdapter} from "../src/feeAdapters/V4FeeAdapter.sol";
import {V4FeePolicy} from "../src/feeAdapters/V4FeePolicy.sol";
import {IV4FeePolicy, IV4ProtocolFeeRuleset} from "../src/interfaces/IV4FeePolicy.sol";

/// @notice A dynamic-fee hook that acts as its own protocol fee ruleset. It reports a protocol fee
/// proportional to its current dynamic LP fee, and in beforeSwap it calls triggerFeeUpdate on the
/// protocolFeeController configured on the PoolManager, so the protocol fee follows the LP fee.
contract MockProportionalFeeHook is BaseTestHooks, IV4ProtocolFeeRuleset {
  using StateLibrary for IPoolManager;

  /// @notice Share of the LP fee the hook reports as protocol fee, in basis points.
  uint256 public constant PROTOCOL_SHARE_BPS = 1000; // 10%

  IPoolManager public immutable manager;

  constructor(IPoolManager _manager) {
    manager = _manager;
  }

  /// @notice Sets the pool's dynamic LP fee on the PoolManager.
  function setLPFee(PoolKey calldata key, uint24 lpFee) external {
    manager.updateDynamicLPFee(key, lpFee);
  }

  /// @notice Protocol fee for one direction, proportional to an LP fee (capped at the max).
  function proportionalFee(uint24 lpFee) public pure returns (uint24) {
    uint256 fee = uint256(lpFee) * PROTOCOL_SHARE_BPS / 10_000;
    if (fee > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) fee = ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
    return uint24(fee);
  }

  /// @inheritdoc IV4ProtocolFeeRuleset
  /// @dev Reads the pool's current dynamic LP fee from the PoolManager.
  function getProtocolFee(PoolKey calldata key) external view returns (uint24) {
    (,,, uint24 lpFee) = manager.getSlot0(key.toId());
    uint24 fee = proportionalFee(lpFee);
    return fee << 12 | fee;
  }

  function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
    return interfaceId == type(IV4ProtocolFeeRuleset).interfaceId || interfaceId == 0x01ffc9a7;
  }

  function beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
    external
    override
    returns (bytes4, BeforeSwapDelta, uint24)
  {
    // PoolManager -> hook -> controller -> policy -> hook.getProtocolFee ->
    // PoolManager.setProtocolFee
    IV4FeeAdapter(manager.protocolFeeController()).triggerFeeUpdate(key);
    return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
  }
}

/// @dev End-to-end with a real PoolManager: the hook reports a protocol fee proportional to its
/// dynamic LP fee, and each swap's beforeSwap pushes that fee to the PoolManager via the adapter.
contract V4DynamicFeeHookProtocolFeeTest is Test {
  using StateLibrary for IPoolManager;

  PoolManager manager;
  V4FeeAdapter adapter;
  V4FeePolicy policy;
  MockProportionalFeeHook hook;
  PoolSwapTest swapRouter;
  PoolModifyLiquidityTest lpRouter;
  PoolKey key;
  PoolId id;

  address owner = makeAddr("owner");
  address feeSetter = makeAddr("feeSetter");
  address tokenJar = makeAddr("tokenJar");

  function setUp() public {
    manager = new PoolManager(owner);
    adapter = new V4FeeAdapter(IPoolManager(address(manager)), tokenJar);
    policy = new V4FeePolicy(owner, feeSetter);
    adapter.setPolicy(IV4FeePolicy(address(policy)));
    vm.prank(owner);
    manager.setProtocolFeeController(address(adapter));

    // Hook with only the beforeSwap permission (no custom accounting).
    address hookAddr = address(uint160(Hooks.BEFORE_SWAP_FLAG) | (uint160(0x4444) << 144));
    deployCodeTo(
      "V4DynamicFeeHookProtocolFee.t.sol:MockProportionalFeeHook",
      abi.encode(address(manager)),
      hookAddr
    );
    hook = MockProportionalFeeHook(hookAddr);

    swapRouter = new PoolSwapTest(manager);
    lpRouter = new PoolModifyLiquidityTest(manager);

    MockERC20 a = new MockERC20("A", "A", 18);
    MockERC20 b = new MockERC20("B", "B", 18);
    (a, b) = address(a) < address(b) ? (a, b) : (b, a);
    for (uint256 i; i < 2; ++i) {
      MockERC20 t = i == 0 ? a : b;
      t.mint(address(this), 1e30);
      t.approve(address(swapRouter), type(uint256).max);
      t.approve(address(lpRouter), type(uint256).max);
    }

    key = PoolKey({
      currency0: Currency.wrap(address(a)),
      currency1: Currency.wrap(address(b)),
      fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
      tickSpacing: 60,
      hooks: IHooks(hookAddr)
    });
    id = key.toId();
    manager.initialize(key, TickMath.getSqrtPriceAtTick(0));
    lpRouter.modifyLiquidity(
      key,
      ModifyLiquidityParams({tickLower: -600, tickUpper: 600, liquidityDelta: 1e24, salt: 0}),
      ""
    );
  }

  function _swap(bool zeroForOne) internal {
    swapRouter.swap(
      key,
      SwapParams({
        zeroForOne: zeroForOne,
        amountSpecified: -1e18,
        sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
      }),
      PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
      ""
    );
  }

  function _protocolFee() internal view returns (uint24 fee) {
    (,, fee,) = IPoolManager(address(manager)).getSlot0(id);
  }

  function test_policyResolvesHookAsRuleset() public {
    hook.setLPFee(key, 3000);
    // No ruleset is set for the hook, it is dynamic-fee, so the policy asks the hook (ERC165).
    assertEq(address(policy.rulesets(address(hook))), address(0));
    assertEq(policy.computeFee(key), uint24(300) << 12 | 300);
  }

  function test_beforeSwap_triggersProportionalProtocolFee() public {
    hook.setLPFee(key, 3000);
    assertEq(_protocolFee(), 0);

    uint24 expected = uint24(300) << 12 | 300;
    vm.expectEmit(address(adapter));
    emit IV4FeeAdapter.FeeUpdateTriggered(address(hook), id, expected);
    _swap(true);

    assertEq(_protocolFee(), expected);
    // The fee set in beforeSwap already applies to this same swap.
    assertGt(manager.protocolFeesAccrued(key.currency0), 0);
    assertEq(manager.protocolFeesAccrued(key.currency1), 0);
  }

  function test_beforeSwap_protocolFeeTracksDynamicLPFee() public {
    hook.setLPFee(key, 3000);
    _swap(true);
    assertEq(_protocolFee(), uint24(300) << 12 | 300);

    // The LP fee changes; the protocol fee is stale until the next swap.
    hook.setLPFee(key, 8000);
    assertEq(_protocolFee(), uint24(300) << 12 | 300);
    _swap(false);
    assertEq(_protocolFee(), uint24(800) << 12 | 800);

    // Capped at MAX_PROTOCOL_FEE for large LP fees.
    hook.setLPFee(key, 50_000);
    _swap(true);
    assertEq(_protocolFee(), uint24(1000) << 12 | 1000);
  }

  function testFuzz_beforeSwap_protocolFeeProportional(uint24 lpFee) public {
    lpFee = uint24(bound(lpFee, 0, 100_000));
    hook.setLPFee(key, lpFee);
    _swap(true);
    uint24 f = hook.proportionalFee(lpFee);
    assertEq(_protocolFee(), f << 12 | f);
  }
}
