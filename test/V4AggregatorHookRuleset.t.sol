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

  bytes32 internal constant USD = bytes32("USD");
  bytes32 internal constant EUR = bytes32("EUR");
  bytes32 internal constant BTC = bytes32("BTC");
  bytes32 internal constant ETH = bytes32("ETH");
  bytes32 internal constant STOCK = bytes32("STOCK");

  Currency internal constant NATIVE = Currency.wrap(address(0));
  Currency internal constant USDC = Currency.wrap(address(0x1001));
  Currency internal constant USDT = Currency.wrap(address(0x1002));
  Currency internal constant DAI = Currency.wrap(address(0x1003));
  Currency internal constant EURC = Currency.wrap(address(0x1101));
  Currency internal constant EURT = Currency.wrap(address(0x1102));
  Currency internal constant WETH = Currency.wrap(address(0x2001));
  Currency internal constant WBTC = Currency.wrap(address(0x3001));
  Currency internal constant CBBTC = Currency.wrap(address(0x3002));
  Currency internal constant STOCK_A = Currency.wrap(address(0x4001));
  Currency internal constant STOCK_B = Currency.wrap(address(0x4002));

  function _entry(Currency currency, bytes32 id)
    internal
    pure
    returns (IV4AggregatorHookRuleset.CurrencyId memory)
  {
    return IV4AggregatorHookRuleset.CurrencyId({currency: currency, id: id});
  }

  /// @dev Five IDs. The ETH ID includes the native currency.
  function _ids() internal pure returns (IV4AggregatorHookRuleset.CurrencyId[] memory ids) {
    ids = new IV4AggregatorHookRuleset.CurrencyId[](11);
    ids[0] = _entry(USDC, USD);
    ids[1] = _entry(USDT, USD);
    ids[2] = _entry(DAI, USD);
    ids[3] = _entry(EURC, EUR);
    ids[4] = _entry(EURT, EUR);
    ids[5] = _entry(WBTC, BTC);
    ids[6] = _entry(CBBTC, BTC);
    ids[7] = _entry(NATIVE, ETH);
    ids[8] = _entry(WETH, ETH);
    ids[9] = _entry(STOCK_A, STOCK);
    ids[10] = _entry(STOCK_B, STOCK);
  }

  /// @dev Puts the currencies in ascending order, as the PoolManager requires.
  function _key(address hook, Currency currencyA, Currency currencyB)
    internal
    pure
    returns (PoolKey memory key)
  {
    (key.currency0, key.currency1) =
      currencyA < currencyB ? (currencyA, currencyB) : (currencyB, currencyA);
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
  // ├── when an ID is zero
  // │   └── it reverts with ZeroId
  // ├── when a currency is in the list two times
  // │   ├── when the two entries have the same ID
  // │   │   └── it reverts with DuplicateCurrency
  // │   └── when the two entries have different IDs
  // │       └── it reverts with DuplicateCurrency
  // ├── when the list is empty
  // │   └── it sets the fees and no ID
  // └── when the list is correct
  //     └── it sets the fees and the IDs

  function testFuzz_constructor_RevertWhen_AnIdIsZero(address token) public {
    IV4AggregatorHookRuleset.CurrencyId[] memory ids = _ids();
    ids[ids.length - 1] = _entry(Currency.wrap(token), bytes32(0));

    vm.expectRevert(abi.encodeWithSelector(IV4AggregatorHookRuleset.ZeroId.selector, token));
    new V4AggregatorHookRuleset(1000, 300, ids);
  }

  function test_constructor_RevertWhen_TheTwoEntriesHaveTheSameId() public {
    IV4AggregatorHookRuleset.CurrencyId[] memory ids = _ids();
    ids[2] = _entry(USDC, USD);

    vm.expectRevert(
      abi.encodeWithSelector(IV4AggregatorHookRuleset.DuplicateCurrency.selector, USDC)
    );
    new V4AggregatorHookRuleset(1000, 300, ids);
  }

  function test_constructor_RevertWhen_TheTwoEntriesHaveDifferentIds() public {
    IV4AggregatorHookRuleset.CurrencyId[] memory ids = _ids();
    ids[4] = _entry(USDC, EUR);

    vm.expectRevert(
      abi.encodeWithSelector(IV4AggregatorHookRuleset.DuplicateCurrency.selector, USDC)
    );
    new V4AggregatorHookRuleset(1000, 300, ids);
  }

  function test_constructor_WhenTheListIsEmpty() public {
    V4AggregatorHookRuleset ruleset =
      new V4AggregatorHookRuleset(1000, 300, new IV4AggregatorHookRuleset.CurrencyId[](0));

    // Then: the constructor sets the fees and no ID.
    assertEq(ruleset.VOLATILE_PAIR_FEE(), 1000);
    assertEq(ruleset.STABLE_PAIR_FEE(), 300);
    assertEq(ruleset.id(USDC), bytes32(0));
    assertEq(ruleset.id(NATIVE), bytes32(0));
    assertFalse(ruleset.isStablePair(USDC, USDT));
  }

  function testFuzz_constructor_WhenTheListIsCorrect(uint24 volatilePairFee, uint24 stablePairFee)
    public
  {
    IV4AggregatorHookRuleset.CurrencyId[] memory ids = _ids();
    V4AggregatorHookRuleset ruleset =
      new V4AggregatorHookRuleset(volatilePairFee, stablePairFee, ids);

    // Then: the constructor sets the fees and the IDs.
    assertEq(ruleset.VOLATILE_PAIR_FEE(), volatilePairFee);
    assertEq(ruleset.STABLE_PAIR_FEE(), stablePairFee);
    for (uint256 i; i < ids.length; ++i) {
      assertEq(ruleset.id(ids[i].currency), ids[i].id);
    }
    assertEq(ruleset.id(Currency.wrap(address(0xdead))), bytes32(0));
  }

  // ============ isStablePair ============
  //
  // isStablePair
  // ├── when the two currencies have the same ID
  // │   └── it returns true for the two orders of the currencies
  // ├── when the two currencies have different IDs
  // │   └── it returns false
  // └── when one or no currency has an ID
  //     └── it returns false

  function testFuzz_isStablePair_WhenTheTwoCurrenciesHaveTheSameId(
    address tokenA,
    address tokenB,
    bytes32 id
  ) public {
    // Given: two different currencies with the same ID.
    vm.assume(tokenA != tokenB && id != bytes32(0));
    Currency currencyA = Currency.wrap(tokenA);
    Currency currencyB = Currency.wrap(tokenB);
    IV4AggregatorHookRuleset.CurrencyId[] memory ids = new IV4AggregatorHookRuleset.CurrencyId[](2);
    ids[0] = _entry(currencyA, id);
    ids[1] = _entry(currencyB, id);
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(1000, 300, ids);

    // Then: isStablePair returns true for the two orders of the currencies.
    assertTrue(ruleset.isStablePair(currencyA, currencyB));
    assertTrue(ruleset.isStablePair(currencyB, currencyA));
  }

  function testFuzz_isStablePair_WhenTheTwoCurrenciesHaveDifferentIds(
    address tokenA,
    address tokenB,
    bytes32 idA,
    bytes32 idB
  ) public {
    // Given: two different currencies with different IDs.
    vm.assume(tokenA != tokenB && idA != bytes32(0) && idB != bytes32(0));
    vm.assume(idA != idB);
    Currency currencyA = Currency.wrap(tokenA);
    Currency currencyB = Currency.wrap(tokenB);
    IV4AggregatorHookRuleset.CurrencyId[] memory ids = new IV4AggregatorHookRuleset.CurrencyId[](2);
    ids[0] = _entry(currencyA, idA);
    ids[1] = _entry(currencyB, idB);
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(1000, 300, ids);

    // Then: isStablePair returns false.
    assertFalse(ruleset.isStablePair(currencyA, currencyB));
    assertFalse(ruleset.isStablePair(currencyB, currencyA));
  }

  function testFuzz_isStablePair_WhenOneOrNoCurrencyHasAnId(
    address tokenA,
    address tokenB,
    uint256 idIndex,
    uint8 idSide
  ) public {
    // Given: the default IDs, and two currencies without an ID.
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(1000, 300, _ids());
    Currency currencyA = Currency.wrap(tokenA);
    Currency currencyB = Currency.wrap(tokenB);
    vm.assume(ruleset.id(currencyA) == bytes32(0) && ruleset.id(currencyB) == bytes32(0));

    // When: at most one of the currencies has an ID.
    IV4AggregatorHookRuleset.CurrencyId[] memory ids = _ids();
    Currency currencyWithId = ids[bound(idIndex, 0, ids.length - 1)].currency;
    if (idSide % 3 == 1) currencyA = currencyWithId;
    else if (idSide % 3 == 2) currencyB = currencyWithId;

    // Then: isStablePair returns false, also when the two currencies are the same.
    assertFalse(ruleset.isStablePair(currencyA, currencyB));
    assertFalse(ruleset.isStablePair(currencyB, currencyA));
  }

  // ============ getProtocolFee ============
  //
  // getProtocolFee
  // ├── when the multiplier of the hook is zero
  // │   └── it reverts with ZeroMultiplier
  // └── when the multiplier of the hook is not zero
  //     ├── when the two currencies have the same ID
  //     │   └── it returns the stable pair fee divided by the multiplier, rounded down
  //     ├── when the two currencies have different IDs
  //     │   └── it returns the volatile pair fee divided by the multiplier, rounded down
  //     ├── when one or no currency has an ID
  //     │   └── it returns the volatile pair fee divided by the multiplier, rounded down
  //     └── when the fee divided by the multiplier is more than MAX_PROTOCOL_FEE
  //         └── it returns MAX_PROTOCOL_FEE
  //
  // The fee is the same in the two directions.

  function test_getProtocolFee_RevertWhen_TheMultiplierOfTheHookIsZero() public {
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(1000, 300, _ids());
    address hook = address(new MockAggregatorHook(0));

    vm.expectRevert(abi.encodeWithSelector(IV4AggregatorHookRuleset.ZeroMultiplier.selector, hook));
    ruleset.getProtocolFee(_key(hook, USDC, WETH));
  }

  function testFuzz_getProtocolFee_WhenTheTwoCurrenciesHaveTheSameId(
    uint24 multiplier,
    uint24 volatilePairFee,
    uint24 stablePairFee,
    uint256 indexA,
    uint256 indexB
  ) public {
    // Given: a hook, and a fee that is at most MAX_PROTOCOL_FEE after the division.
    multiplier = uint24(bound(multiplier, 1, 1000));
    stablePairFee =
      uint24(bound(stablePairFee, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE * multiplier));
    IV4AggregatorHookRuleset.CurrencyId[] memory ids = _ids();
    V4AggregatorHookRuleset ruleset =
      new V4AggregatorHookRuleset(volatilePairFee, stablePairFee, ids);
    address hook = address(new MockAggregatorHook(multiplier));

    // When: the two currencies are different and have the same ID.
    IV4AggregatorHookRuleset.CurrencyId memory entryA = ids[bound(indexA, 0, ids.length - 1)];
    IV4AggregatorHookRuleset.CurrencyId memory entryB = ids[bound(indexB, 0, ids.length - 1)];
    vm.assume(!(entryA.currency == entryB.currency) && entryA.id == entryB.id);

    // Then: getProtocolFee returns the stable pair fee divided by the multiplier, rounded down.
    assertEq(
      ruleset.getProtocolFee(_key(hook, entryA.currency, entryB.currency)),
      _packed(stablePairFee / multiplier)
    );
  }

  function testFuzz_getProtocolFee_WhenTheTwoCurrenciesHaveDifferentIds(
    uint24 multiplier,
    uint24 volatilePairFee,
    uint24 stablePairFee,
    uint256 indexA,
    uint256 indexB
  ) public {
    // Given: a hook, and a fee that is at most MAX_PROTOCOL_FEE after the division.
    multiplier = uint24(bound(multiplier, 1, 1000));
    volatilePairFee =
      uint24(bound(volatilePairFee, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE * multiplier));
    IV4AggregatorHookRuleset.CurrencyId[] memory ids = _ids();
    V4AggregatorHookRuleset ruleset =
      new V4AggregatorHookRuleset(volatilePairFee, stablePairFee, ids);
    address hook = address(new MockAggregatorHook(multiplier));

    // When: each currency has an ID, but the two IDs are different.
    IV4AggregatorHookRuleset.CurrencyId memory entryA = ids[bound(indexA, 0, ids.length - 1)];
    IV4AggregatorHookRuleset.CurrencyId memory entryB = ids[bound(indexB, 0, ids.length - 1)];
    vm.assume(entryA.id != entryB.id);

    // Then: getProtocolFee returns the volatile pair fee divided by the multiplier, rounded down.
    assertEq(
      ruleset.getProtocolFee(_key(hook, entryA.currency, entryB.currency)),
      _packed(volatilePairFee / multiplier)
    );
  }

  function testFuzz_getProtocolFee_WhenOneOrNoCurrencyHasAnId(
    uint24 multiplier,
    uint24 volatilePairFee,
    uint24 stablePairFee,
    address tokenA,
    address tokenB,
    uint256 idIndex,
    uint8 idSide
  ) public {
    // Given: a hook, and a fee that is at most MAX_PROTOCOL_FEE after the division.
    multiplier = uint24(bound(multiplier, 1, 1000));
    volatilePairFee =
      uint24(bound(volatilePairFee, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE * multiplier));
    IV4AggregatorHookRuleset.CurrencyId[] memory ids = _ids();
    V4AggregatorHookRuleset ruleset =
      new V4AggregatorHookRuleset(volatilePairFee, stablePairFee, ids);
    address hook = address(new MockAggregatorHook(multiplier));

    // When: the currencies have no ID, except for at most one of them.
    Currency currencyA = Currency.wrap(tokenA);
    Currency currencyB = Currency.wrap(tokenB);
    vm.assume(ruleset.id(currencyA) == bytes32(0) && ruleset.id(currencyB) == bytes32(0));
    Currency currencyWithId = ids[bound(idIndex, 0, ids.length - 1)].currency;
    if (idSide % 3 == 1) currencyA = currencyWithId;
    else if (idSide % 3 == 2) currencyB = currencyWithId;

    // Then: getProtocolFee returns the volatile pair fee divided by the multiplier, rounded down.
    assertEq(
      ruleset.getProtocolFee(_key(hook, currencyA, currencyB)),
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
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(volatilePairFee, 0, _ids());
    address hook = address(new MockAggregatorHook(multiplier));

    // Then: getProtocolFee returns MAX_PROTOCOL_FEE.
    assertEq(
      ruleset.getProtocolFee(_key(hook, USDC, WETH)), _packed(ProtocolFeeLibrary.MAX_PROTOCOL_FEE)
    );
  }

  // ============ Like-for-like pairs ============
  //
  // A pair is stable only when its two currencies have the same ID. A currency with an ID
  // does not make its other pairs stable.

  function test_getProtocolFee_twoCurrenciesWithDifferentIdsPayTheVolatileFee() public {
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(1000, 300, _ids());
    address hook = address(new MockAggregatorHook(AGGREGATOR_MULTIPLIER));

    // USD/USD and EUR/EUR pairs are stable, but a USD/EUR pair is not.
    assertEq(ruleset.getProtocolFee(_key(hook, USDC, USDT)), _packed(12));
    assertEq(ruleset.getProtocolFee(_key(hook, EURC, EURT)), _packed(12));
    assertEq(ruleset.getProtocolFee(_key(hook, USDC, EURC)), _packed(40));
  }

  function test_getProtocolFee_twoTokensOfTheSameAssetPayTheStableFee() public {
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(1000, 300, _ids());
    address hook = address(new MockAggregatorHook(AGGREGATOR_MULTIPLIER));

    // Two tokens of the same asset are a stable pair, but their pairs with USDC are not.
    assertEq(ruleset.getProtocolFee(_key(hook, WBTC, CBBTC)), _packed(12));
    assertEq(ruleset.getProtocolFee(_key(hook, NATIVE, WETH)), _packed(12));
    assertEq(ruleset.getProtocolFee(_key(hook, STOCK_A, STOCK_B)), _packed(12));
    assertEq(ruleset.getProtocolFee(_key(hook, WBTC, USDC)), _packed(40));
    assertEq(ruleset.getProtocolFee(_key(hook, NATIVE, USDC)), _packed(40));
    assertEq(ruleset.getProtocolFee(_key(hook, STOCK_A, USDC)), _packed(40));
  }

  // ============ Hooks with different multipliers ============
  //
  // Each hook charges the protocol fee times its own multiplier. Mainnet has hooks with a
  // multiplier of 25 and hooks with a multiplier of 10. The ruleset gives each hook the protocol
  // fee that makes it charge the same fee.

  function test_getProtocolFee_hooksWithDifferentMultipliersChargeTheSameFee() public {
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(1000, 300, _ids());
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
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(1000, 300, _ids());
    address hook = address(new MockAggregatorHook(AGGREGATOR_MULTIPLIER));

    assertEq(ruleset.getProtocolFee(_key(hook, USDC, WETH)), 0x028028);
    assertEq(ruleset.getProtocolFee(_key(hook, USDC, USDT)), 0x00c00c);
  }

  function test_baseConfiguration_returnsTheProposalFees() public {
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(300, 100, _ids());
    address hook = address(new MockAggregatorHook(AGGREGATOR_MULTIPLIER));

    assertEq(ruleset.getProtocolFee(_key(hook, USDC, WETH)), _packed(12));
    assertEq(ruleset.getProtocolFee(_key(hook, USDC, USDT)), _packed(4));
  }

  // ============ V4FeePolicy integration ============

  function test_policy_returnsTheRulesetFeeForAnAssignedAggregatorHook() public {
    // Given: a ruleset assigned to an aggregator hook.
    V4FeePolicy policy = new V4FeePolicy(address(this), address(this));
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(1000, 300, _ids());
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
    V4AggregatorHookRuleset ruleset = new V4AggregatorHookRuleset(1000, 300, _ids());
    policy.setProtocolFeeRuleset(AGGREGATOR_HOOK_RULESET_KEY, ruleset);

    assertEq(address(policy.rulesets(AGGREGATOR_HOOK_RULESET_KEY)), address(ruleset));
  }
}
