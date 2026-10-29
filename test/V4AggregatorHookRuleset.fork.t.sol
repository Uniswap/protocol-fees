// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

import {V4AggregatorHookRuleset} from "../src/feeAdapters/rulesets/V4AggregatorHookRuleset.sol";
import {
  IAggregatorHookProtocolFees
} from "../src/interfaces/external/IAggregatorHookProtocolFees.sol";

/// @notice Reads the multiplier of deployed aggregator hooks on mainnet. The hook addresses are
/// verified contracts on eth.blockscout.com.
contract V4AggregatorHookRulesetMainnetForkTest is Test {
  /// @dev UniswapV3Aggregator, protocolFeeMultiplier 25, protocolFeeFlags 1 << 11.
  address internal constant UNISWAP_V3_AGGREGATOR = 0x0359E30D4E8E098f1033f948182F88E43EfD6888;

  /// @dev StableSwapNGAggregator, protocolFeeMultiplier 25, protocolFeeFlags 1 << 11.
  address internal constant STABLESWAP_NG_AGGREGATOR = 0xC2D4CB52BD609D7041A2b0071C6F7d84Ac3D6888;

  /// @dev LitePSMAggregator, protocolFeeMultiplier 10, protocolFeeFlags 1 << 12.
  address internal constant LITE_PSM_AGGREGATOR = 0x958942aF77dCD973B815b2A16BD88a5134c46888;

  Currency internal constant USDC = Currency.wrap(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
  Currency internal constant USDT = Currency.wrap(0xdAC17F958D2ee523a2206206994597C13D831ec7);
  Currency internal constant WETH = Currency.wrap(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

  V4AggregatorHookRuleset internal ruleset;

  function setUp() public {
    bool shouldRun = vm.envOr("SHOULD_FORK_TEST", false);
    vm.skip(!shouldRun);

    vm.createSelectFork("mainnet", 26_300_005);
    assertEq(block.chainid, 1, "Not on mainnet");

    Currency[] memory stablecoins = new Currency[](2);
    stablecoins[0] = USDC;
    stablecoins[1] = USDT;
    ruleset = new V4AggregatorHookRuleset(1000, 300, stablecoins);
  }

  function _key(address hook, Currency currency0, Currency currency1)
    internal
    pure
    returns (PoolKey memory key)
  {
    key.currency0 = currency0;
    key.currency1 = currency1;
    key.tickSpacing = 1;
    key.hooks = IHooks(hook);
  }

  function test_fork_hooksWithMultiplier25_getTheLiveProtocolFees() public view {
    address[2] memory hooks = [UNISWAP_V3_AGGREGATOR, STABLESWAP_NG_AGGREGATOR];
    for (uint256 i; i < hooks.length; ++i) {
      assertEq(IAggregatorHookProtocolFees(hooks[i]).protocolFeeMultiplier(), 25);
      // 10 bps and 3 bps, divided by 25.
      assertEq(ruleset.getProtocolFee(_key(hooks[i], USDC, WETH)), 0x028028);
      assertEq(ruleset.getProtocolFee(_key(hooks[i], USDC, USDT)), 0x00c00c);
    }
  }

  function test_fork_hookWithMultiplier10_getsAProtocolFeeForTheSameCharge() public view {
    assertEq(IAggregatorHookProtocolFees(LITE_PSM_AGGREGATOR).protocolFeeMultiplier(), 10);
    // 10 bps and 3 bps, divided by 10.
    assertEq(ruleset.getProtocolFee(_key(LITE_PSM_AGGREGATOR, USDC, WETH)), 100 << 12 | 100);
    assertEq(ruleset.getProtocolFee(_key(LITE_PSM_AGGREGATOR, USDC, USDT)), 30 << 12 | 30);
  }
}
