// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";

import {V4FeePolicy} from "../src/feeAdapters/V4FeePolicy.sol";
import {V4AggregatorHookRuleset} from "../src/feeAdapters/rulesets/V4AggregatorHookRuleset.sol";
import {
  IV4AggregatorHookRuleset,
  AGGREGATOR_HOOK_RULESET_KEY
} from "../src/interfaces/IV4AggregatorHookRuleset.sol";

/// @dev Each section starts with the branch tree of one function. The tests are in the same
/// sequence as the tree. The configuration is set at deployment, thus each test deploys its own
/// ruleset.
contract V4AggregatorHookRulesetTest is Test {
  /// @dev The multiplier of BaseAggregatorHook in Uniswap/v4-hooks-public.
  uint24 internal constant HOOK_FEE_MULTIPLIER = 25;

  Currency internal constant USDC = Currency.wrap(address(0x1001));
  Currency internal constant USDT = Currency.wrap(address(0x1002));
  Currency internal constant DAI = Currency.wrap(address(0x1003));
  Currency internal constant WETH = Currency.wrap(address(0x2001));
  Currency internal constant NATIVE = Currency.wrap(address(0));

  function _stablecoins() internal pure returns (Currency[] memory stablecoins) {
    stablecoins = new Currency[](3);
    stablecoins[0] = USDC;
    stablecoins[1] = USDT;
    stablecoins[2] = DAI;
  }

  function _key(Currency currency0, Currency currency1) internal pure returns (PoolKey memory key) {
    key.currency0 = currency0;
    key.currency1 = currency1;
    key.fee = 0;
    key.tickSpacing = 1;
    key.hooks = IHooks(address(0));
  }

  function _packed(uint24 perDirection) internal pure returns (uint24) {
    return perDirection << 12 | perDirection;
  }

  // ============ constructor ============
  //
  // constructor
  // ├── when the multiplier is zero
  // │   └── it reverts with ZeroMultiplier
  // ├── when a fee is not a multiple of the multiplier
  // │   └── it reverts with FeeNotDivisibleByMultiplier
  // ├── when a fee divided by the multiplier is more than MAX_PROTOCOL_FEE
  // │   └── it reverts with InvalidFeeValue
  // ├── when a stablecoin is the native currency
  // │   └── it reverts with NativeCurrencyNotStablecoin
  // ├── when a stablecoin is in the list twice
  // │   └── it reverts with DuplicateStablecoin
  // └── when the configuration is correct
  //     └── it sets the fees, the multiplier and the stablecoins

  function testFuzz_constructor_RevertWhen_TheMultiplierIsZero(
    uint24 volatilePairFee,
    uint24 stablePairFee
  ) public {
    vm.expectRevert(IV4AggregatorHookRuleset.ZeroMultiplier.selector);
    new V4AggregatorHookRuleset(volatilePairFee, stablePairFee, 0, _stablecoins());
  }

  function testFuzz_constructor_RevertWhen_TheVolatilePairFeeIsNotAMultipleOfTheMultiplier(
    uint24 multiplier,
    uint24 protocolFee,
    uint24 remainder
  ) public {
    // When: the volatile pair fee is a valid protocol fee times the multiplier, plus a remainder.
    multiplier = uint24(bound(multiplier, 2, 1000));
    protocolFee = uint24(bound(protocolFee, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
    remainder = uint24(bound(remainder, 1, multiplier - 1));
    uint24 fee = protocolFee * multiplier + remainder;

    // Then: the constructor reverts with FeeNotDivisibleByMultiplier.
    vm.expectRevert(
      abi.encodeWithSelector(
        IV4AggregatorHookRuleset.FeeNotDivisibleByMultiplier.selector, fee, multiplier
      )
    );
    new V4AggregatorHookRuleset(fee, 0, multiplier, _stablecoins());
  }

  function testFuzz_constructor_RevertWhen_TheStablePairFeeIsNotAMultipleOfTheMultiplier(
    uint24 multiplier,
    uint24 protocolFee,
    uint24 remainder
  ) public {
    // When: the stable pair fee is a valid protocol fee times the multiplier, plus a remainder.
    multiplier = uint24(bound(multiplier, 2, 1000));
    protocolFee = uint24(bound(protocolFee, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
    remainder = uint24(bound(remainder, 1, multiplier - 1));
    uint24 fee = protocolFee * multiplier + remainder;

    // Then: the constructor reverts with FeeNotDivisibleByMultiplier.
    vm.expectRevert(
      abi.encodeWithSelector(
        IV4AggregatorHookRuleset.FeeNotDivisibleByMultiplier.selector, fee, multiplier
      )
    );
    new V4AggregatorHookRuleset(0, fee, multiplier, _stablecoins());
  }

  function testFuzz_constructor_RevertWhen_AFeeDividedByTheMultiplierIsMoreThanMaxProtocolFee(
    uint24 multiplier,
    uint24 protocolFee,
    bool stable
  ) public {
    // When: a fee is the multiplier times a protocol fee above MAX_PROTOCOL_FEE.
    multiplier = uint24(bound(multiplier, 1, 1000));
    protocolFee = uint24(
      bound(protocolFee, ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1, type(uint24).max / multiplier)
    );
    uint24 fee = protocolFee * multiplier;

    // Then: the constructor reverts with InvalidFeeValue.
    vm.expectRevert(abi.encodeWithSelector(IV4AggregatorHookRuleset.InvalidFeeValue.selector, fee));
    if (stable) new V4AggregatorHookRuleset(0, fee, multiplier, _stablecoins());
    else new V4AggregatorHookRuleset(fee, 0, multiplier, _stablecoins());
  }

  function test_constructor_RevertWhen_AStablecoinIsTheNativeCurrency() public {
    Currency[] memory stablecoins = _stablecoins();
    stablecoins[1] = NATIVE;

    vm.expectRevert(IV4AggregatorHookRuleset.NativeCurrencyNotStablecoin.selector);
    new V4AggregatorHookRuleset(1000, 300, HOOK_FEE_MULTIPLIER, stablecoins);
  }

  function test_constructor_RevertWhen_AStablecoinIsInTheListTwice() public {
    Currency[] memory stablecoins = _stablecoins();
    stablecoins[2] = USDC;

    vm.expectRevert(
      abi.encodeWithSelector(IV4AggregatorHookRuleset.DuplicateStablecoin.selector, USDC)
    );
    new V4AggregatorHookRuleset(1000, 300, HOOK_FEE_MULTIPLIER, stablecoins);
  }

  function testFuzz_constructor_WhenTheConfigurationIsCorrect(
    uint24 multiplier,
    uint24 volatileProtocolFee,
    uint24 stableProtocolFee
  ) public {
    // When: each fee is the multiplier times a protocol fee at or below MAX_PROTOCOL_FEE.
    multiplier = uint24(bound(multiplier, 1, 1000));
    volatileProtocolFee = uint24(bound(volatileProtocolFee, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
    stableProtocolFee = uint24(bound(stableProtocolFee, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
    Currency[] memory stablecoins = _stablecoins();

    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(
      volatileProtocolFee * multiplier, stableProtocolFee * multiplier, multiplier, stablecoins
    );

    // Then: the constructor sets the fees, the multiplier and the stablecoins.
    assertEq(ruleset.HOOK_FEE_MULTIPLIER(), multiplier);
    assertEq(ruleset.VOLATILE_PAIR_FEE(), volatileProtocolFee * multiplier);
    assertEq(ruleset.STABLE_PAIR_FEE(), stableProtocolFee * multiplier);
    assertEq(ruleset.stablecoinsLength(), stablecoins.length);
    for (uint256 i; i < stablecoins.length; ++i) {
      assertEq(Currency.unwrap(ruleset.stablecoins(i)), Currency.unwrap(stablecoins[i]));
      assertTrue(ruleset.isStablecoin(stablecoins[i]));
    }
    assertFalse(ruleset.isStablecoin(WETH));
    assertFalse(ruleset.isStablecoin(NATIVE));
  }

  // ============ getProtocolFee ============
  //
  // getProtocolFee
  // ├── when the two currencies are stablecoins
  // │   └── it returns the stable pair fee divided by the multiplier, in the two directions
  // └── when one or no currency is a stablecoin
  //     └── it returns the volatile pair fee divided by the multiplier, in the two directions

  function testFuzz_getProtocolFee_WhenTheTwoCurrenciesAreStablecoins(
    uint24 multiplier,
    uint24 volatileProtocolFee,
    uint24 stableProtocolFee,
    uint256 index0,
    uint256 index1
  ) public {
    // Given: a ruleset.
    multiplier = uint24(bound(multiplier, 1, 1000));
    volatileProtocolFee = uint24(bound(volatileProtocolFee, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
    stableProtocolFee = uint24(bound(stableProtocolFee, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
    Currency[] memory stablecoins = _stablecoins();
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(
      volatileProtocolFee * multiplier, stableProtocolFee * multiplier, multiplier, stablecoins
    );

    // When: the two currencies are stablecoins.
    Currency currency0 = stablecoins[bound(index0, 0, stablecoins.length - 1)];
    Currency currency1 = stablecoins[bound(index1, 0, stablecoins.length - 1)];

    // Then: getProtocolFee returns the stable pair fee divided by the multiplier.
    assertEq(ruleset.getProtocolFee(_key(currency0, currency1)), _packed(stableProtocolFee));
  }

  function testFuzz_getProtocolFee_WhenOneOrNoCurrencyIsAStablecoin(
    uint24 multiplier,
    uint24 volatileProtocolFee,
    uint24 stableProtocolFee,
    address token0,
    address token1,
    uint256 stableIndex,
    uint8 stableSide
  ) public {
    // Given: a ruleset.
    multiplier = uint24(bound(multiplier, 1, 1000));
    volatileProtocolFee = uint24(bound(volatileProtocolFee, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
    stableProtocolFee = uint24(bound(stableProtocolFee, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
    Currency[] memory stablecoins = _stablecoins();
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(
      volatileProtocolFee * multiplier, stableProtocolFee * multiplier, multiplier, stablecoins
    );

    // When: the currencies are not stablecoins, except for at most one of them.
    Currency currency0 = Currency.wrap(token0);
    Currency currency1 = Currency.wrap(token1);
    vm.assume(!ruleset.isStablecoin(currency0) && !ruleset.isStablecoin(currency1));
    Currency stablecoin = stablecoins[bound(stableIndex, 0, stablecoins.length - 1)];
    if (stableSide % 3 == 1) currency0 = stablecoin;
    else if (stableSide % 3 == 2) currency1 = stablecoin;

    // Then: getProtocolFee returns the volatile pair fee divided by the multiplier.
    assertEq(ruleset.getProtocolFee(_key(currency0, currency1)), _packed(volatileProtocolFee));
  }

  // ============ Deployment configurations ============
  //
  // Proposal 6 sets 10 bps on volatile pairs and 3 bps on stable pairs, and 3 bps and 1 bp on
  // Base. Mainnet V4FeePolicy 0x1cd822b70a0591420F65E94b9B3A0D0b0fB3a314 stores the volatile fee
  // as 0x028028 and the stable fee as 0x00c00c.

  function test_mainnetConfiguration_returnsTheLiveFees() public {
    V4AggregatorHookRuleset ruleset =
      new V4AggregatorHookRuleset(1000, 300, HOOK_FEE_MULTIPLIER, _stablecoins());

    assertEq(ruleset.getProtocolFee(_key(USDC, WETH)), 0x028028);
    assertEq(ruleset.getProtocolFee(_key(USDC, USDT)), 0x00c00c);
  }

  function test_baseConfiguration_returnsTheProposalFees() public {
    V4AggregatorHookRuleset ruleset =
      new V4AggregatorHookRuleset(300, 100, HOOK_FEE_MULTIPLIER, _stablecoins());

    assertEq(ruleset.getProtocolFee(_key(USDC, WETH)), _packed(12));
    assertEq(ruleset.getProtocolFee(_key(USDC, USDT)), _packed(4));
  }

  // ============ V4FeePolicy integration ============

  function test_policy_returnsTheRulesetFeeForAnAssignedAggregatorHook() public {
    // Given: a ruleset assigned to an aggregator hook, which returns a delta from beforeSwap.
    V4FeePolicy policy = new V4FeePolicy(address(this), address(this));
    V4AggregatorHookRuleset ruleset =
      new V4AggregatorHookRuleset(1000, 300, HOOK_FEE_MULTIPLIER, _stablecoins());
    address hook = address(
      uint160(uint256(keccak256("aggregator hook")) << 14) | Hooks.BEFORE_SWAP_FLAG
        | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
    );
    policy.setProtocolFeeRuleset(hook, ruleset);

    // Then: the policy returns the fee of the ruleset for the hook's pools.
    PoolKey memory volatilePool = _key(USDC, WETH);
    volatilePool.hooks = IHooks(hook);
    PoolKey memory stablePool = _key(USDC, USDT);
    stablePool.hooks = IHooks(hook);
    assertEq(policy.computeFee(volatilePool), 0x028028);
    assertEq(policy.computeFee(stablePool), 0x00c00c);
  }

  function test_policy_canRegisterTheRulesetAtTheAggregatorKey() public {
    // The key is the address derived from the label "AGGREGATOR".
    assertEq(AGGREGATOR_HOOK_RULESET_KEY, address(uint160(uint256(keccak256("AGGREGATOR")))));

    V4FeePolicy policy = new V4FeePolicy(address(this), address(this));
    V4AggregatorHookRuleset ruleset =
      new V4AggregatorHookRuleset(1000, 300, HOOK_FEE_MULTIPLIER, _stablecoins());
    policy.setProtocolFeeRuleset(AGGREGATOR_HOOK_RULESET_KEY, ruleset);

    assertEq(address(policy.rulesets(AGGREGATOR_HOOK_RULESET_KEY)), address(ruleset));
  }
}
