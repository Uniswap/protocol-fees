// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";

import {V4FeePolicy} from "../src/feeAdapters/V4FeePolicy.sol";
import {V4AggregatorHookRuleset} from "../src/feeAdapters/rulesets/V4AggregatorHookRuleset.sol";
import {
  IV4AggregatorHookRuleset,
  AGGREGATOR_HOOK_RULESET_KEY
} from "../src/interfaces/IV4AggregatorHookRuleset.sol";
import {MockAggregatorHook} from "./mocks/MockAggregatorHook.sol";

/// @dev Each section starts with the branch tree of one function. The tests are in the same
/// sequence as the tree. The configuration is set at deployment, thus each test deploys its own
/// ruleset.
contract V4AggregatorHookRulesetTest is Test {
  /// @dev The multiplier of most aggregator hooks on mainnet.
  uint24 internal constant AGGREGATOR_MULTIPLIER = 25;

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

  function _key(address hook, Currency currency0, Currency currency1)
    internal
    pure
    returns (PoolKey memory key)
  {
    key.currency0 = currency0;
    key.currency1 = currency1;
    key.fee = 0;
    key.tickSpacing = 1;
    key.hooks = IHooks(hook);
  }

  function _packed(uint256 perDirection) internal pure returns (uint24) {
    return uint24(perDirection << 12 | perDirection);
  }

  // ============ constructor ============
  //
  // constructor
  // ├── when a stablecoin is the native currency
  // │   └── it reverts with NativeCurrencyNotStablecoin
  // ├── when a stablecoin is in the list twice
  // │   └── it reverts with DuplicateStablecoin
  // └── when the stablecoins are correct
  //     └── it sets the fees and the stablecoins

  function test_constructor_RevertWhen_AStablecoinIsTheNativeCurrency() public {
    Currency[] memory stablecoins = _stablecoins();
    stablecoins[1] = NATIVE;

    vm.expectRevert(IV4AggregatorHookRuleset.NativeCurrencyNotStablecoin.selector);
    new V4AggregatorHookRuleset(1000, 300, stablecoins);
  }

  function test_constructor_RevertWhen_AStablecoinIsInTheListTwice() public {
    Currency[] memory stablecoins = _stablecoins();
    stablecoins[2] = USDC;

    vm.expectRevert(
      abi.encodeWithSelector(IV4AggregatorHookRuleset.DuplicateStablecoin.selector, USDC)
    );
    new V4AggregatorHookRuleset(1000, 300, stablecoins);
  }

  function testFuzz_constructor_WhenTheStablecoinsAreCorrect(
    uint24 volatilePairFee,
    uint24 stablePairFee
  ) public {
    Currency[] memory stablecoins = _stablecoins();
    V4AggregatorHookRuleset ruleset =
      new V4AggregatorHookRuleset(volatilePairFee, stablePairFee, stablecoins);

    // Then: the constructor sets the fees and the stablecoins.
    assertEq(ruleset.VOLATILE_PAIR_FEE(), volatilePairFee);
    assertEq(ruleset.STABLE_PAIR_FEE(), stablePairFee);
    for (uint256 i; i < stablecoins.length; ++i) {
      assertTrue(ruleset.isStablecoin(stablecoins[i]));
    }
    assertFalse(ruleset.isStablecoin(WETH));
    assertFalse(ruleset.isStablecoin(NATIVE));
  }

  // ============ getProtocolFee ============
  //
  // getProtocolFee
  // ├── when the multiplier of the hook is zero
  // │   └── it reverts with ZeroMultiplier
  // └── when the multiplier of the hook is not zero
  //     ├── when the two currencies are stablecoins
  //     │   └── it returns the stable pair fee divided by the multiplier, rounded down
  //     ├── when one or no currency is a stablecoin
  //     │   └── it returns the volatile pair fee divided by the multiplier, rounded down
  //     └── when the fee divided by the multiplier is more than MAX_PROTOCOL_FEE
  //         └── it returns MAX_PROTOCOL_FEE
  //
  // The fee is the same in the two directions.

  function test_getProtocolFee_RevertWhen_TheMultiplierOfTheHookIsZero() public {
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(1000, 300, _stablecoins());
    address hook = address(new MockAggregatorHook(0));

    vm.expectRevert(abi.encodeWithSelector(IV4AggregatorHookRuleset.ZeroMultiplier.selector, hook));
    ruleset.getProtocolFee(_key(hook, USDC, WETH));
  }

  function testFuzz_getProtocolFee_WhenTheTwoCurrenciesAreStablecoins(
    uint24 multiplier,
    uint24 volatilePairFee,
    uint24 stablePairFee,
    uint256 index0,
    uint256 index1
  ) public {
    // Given: a hook, and a fee that is at most MAX_PROTOCOL_FEE after the division.
    multiplier = uint24(bound(multiplier, 1, 1000));
    stablePairFee =
      uint24(bound(stablePairFee, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE * multiplier));
    Currency[] memory stablecoins = _stablecoins();
    V4AggregatorHookRuleset ruleset =
      new V4AggregatorHookRuleset(volatilePairFee, stablePairFee, stablecoins);
    address hook = address(new MockAggregatorHook(multiplier));

    // When: the two currencies are stablecoins.
    Currency currency0 = stablecoins[bound(index0, 0, stablecoins.length - 1)];
    Currency currency1 = stablecoins[bound(index1, 0, stablecoins.length - 1)];

    // Then: getProtocolFee returns the stable pair fee divided by the multiplier, rounded down.
    assertEq(
      ruleset.getProtocolFee(_key(hook, currency0, currency1)), _packed(stablePairFee / multiplier)
    );
  }

  function testFuzz_getProtocolFee_WhenOneOrNoCurrencyIsAStablecoin(
    uint24 multiplier,
    uint24 volatilePairFee,
    uint24 stablePairFee,
    address token0,
    address token1,
    uint256 stableIndex,
    uint8 stableSide
  ) public {
    // Given: a hook, and a fee that is at most MAX_PROTOCOL_FEE after the division.
    multiplier = uint24(bound(multiplier, 1, 1000));
    volatilePairFee =
      uint24(bound(volatilePairFee, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE * multiplier));
    Currency[] memory stablecoins = _stablecoins();
    V4AggregatorHookRuleset ruleset =
      new V4AggregatorHookRuleset(volatilePairFee, stablePairFee, stablecoins);
    address hook = address(new MockAggregatorHook(multiplier));

    // When: the currencies are not stablecoins, except for at most one of them.
    Currency currency0 = Currency.wrap(token0);
    Currency currency1 = Currency.wrap(token1);
    vm.assume(!ruleset.isStablecoin(currency0) && !ruleset.isStablecoin(currency1));
    Currency stablecoin = stablecoins[bound(stableIndex, 0, stablecoins.length - 1)];
    if (stableSide % 3 == 1) currency0 = stablecoin;
    else if (stableSide % 3 == 2) currency1 = stablecoin;

    // Then: getProtocolFee returns the volatile pair fee divided by the multiplier, rounded down.
    assertEq(
      ruleset.getProtocolFee(_key(hook, currency0, currency1)),
      _packed(volatilePairFee / multiplier)
    );
  }

  function testFuzz_getProtocolFee_WhenTheFeeDividedByTheMultiplierIsMoreThanMaxProtocolFee(
    uint24 multiplier,
    uint24 volatilePairFee
  ) public {
    // Given: a fee that is more than MAX_PROTOCOL_FEE after the division.
    multiplier = uint24(bound(multiplier, 1, 1000));
    volatilePairFee = uint24(
      bound(
        volatilePairFee, (ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1) * multiplier, type(uint24).max
      )
    );
    V4AggregatorHookRuleset ruleset =
      new V4AggregatorHookRuleset(volatilePairFee, 0, _stablecoins());
    address hook = address(new MockAggregatorHook(multiplier));

    // Then: getProtocolFee returns MAX_PROTOCOL_FEE.
    assertEq(
      ruleset.getProtocolFee(_key(hook, USDC, WETH)), _packed(ProtocolFeeLibrary.MAX_PROTOCOL_FEE)
    );
  }

  // ============ Hooks with different multipliers ============
  //
  // Each hook charges the protocol fee times its own multiplier. Mainnet has hooks with a
  // multiplier of 25 and hooks with a multiplier of 10. The ruleset gives each hook the protocol
  // fee that makes it charge the same fee.

  function test_getProtocolFee_hooksWithDifferentMultipliersChargeTheSameFee() public {
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(1000, 300, _stablecoins());
    address hook25 = address(new MockAggregatorHook(25));
    address hook10 = address(new MockAggregatorHook(10));

    assertEq(ruleset.getProtocolFee(_key(hook25, USDC, WETH)), _packed(40));
    assertEq(ruleset.getProtocolFee(_key(hook10, USDC, WETH)), _packed(100));
    assertEq(ruleset.getProtocolFee(_key(hook25, USDC, USDT)), _packed(12));
    assertEq(ruleset.getProtocolFee(_key(hook10, USDC, USDT)), _packed(30));
  }

  // ============ Deployment configurations ============
  //
  // Proposal 6 sets 10 bps on volatile pairs and 3 bps on stable pairs, and 3 bps and 1 bp on
  // Base. Mainnet V4FeePolicy 0x1cd822b70a0591420F65E94b9B3A0D0b0fB3a314 stores the volatile fee
  // as 0x028028 and the stable fee as 0x00c00c, for hooks with a multiplier of 25.

  function test_mainnetConfiguration_returnsTheLiveFees() public {
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(1000, 300, _stablecoins());
    address hook = address(new MockAggregatorHook(AGGREGATOR_MULTIPLIER));

    assertEq(ruleset.getProtocolFee(_key(hook, USDC, WETH)), 0x028028);
    assertEq(ruleset.getProtocolFee(_key(hook, USDC, USDT)), 0x00c00c);
  }

  function test_baseConfiguration_returnsTheProposalFees() public {
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(300, 100, _stablecoins());
    address hook = address(new MockAggregatorHook(AGGREGATOR_MULTIPLIER));

    assertEq(ruleset.getProtocolFee(_key(hook, USDC, WETH)), _packed(12));
    assertEq(ruleset.getProtocolFee(_key(hook, USDC, USDT)), _packed(4));
  }

  // ============ V4FeePolicy integration ============

  function test_policy_returnsTheRulesetFeeForAnAssignedAggregatorHook() public {
    // Given: a ruleset assigned to an aggregator hook.
    V4FeePolicy policy = new V4FeePolicy(address(this), address(this));
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(1000, 300, _stablecoins());
    address hook = address(new MockAggregatorHook(AGGREGATOR_MULTIPLIER));
    policy.setProtocolFeeRuleset(hook, ruleset);

    // Then: the policy returns the fee of the ruleset for the hook's pools.
    assertEq(policy.computeFee(_key(hook, USDC, WETH)), 0x028028);
    assertEq(policy.computeFee(_key(hook, USDC, USDT)), 0x00c00c);
  }

  function test_policy_canRegisterTheRulesetAtTheAggregatorKey() public {
    // The key is the address derived from the label "AGGREGATOR".
    assertEq(AGGREGATOR_HOOK_RULESET_KEY, address(uint160(uint256(keccak256("AGGREGATOR")))));

    V4FeePolicy policy = new V4FeePolicy(address(this), address(this));
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(1000, 300, _stablecoins());
    policy.setProtocolFeeRuleset(AGGREGATOR_HOOK_RULESET_KEY, ruleset);

    assertEq(address(policy.rulesets(AGGREGATOR_HOOK_RULESET_KEY)), address(ruleset));
  }
}
