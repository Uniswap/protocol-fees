// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {V4FeeController} from "src/feeControllers/V4FeeController.sol";
import {MockPoolManager} from "./mocks/MockPoolManager.sol";
import {PhoenixTestBase} from "./utils/PhoenixTestBase.sol";

contract TestV4FeeController is PhoenixTestBase {
  MockPoolManager poolManager;
  V4FeeController feeController;

  Currency mockNative;
  Currency mockCurrency;

  function setUp() public override {
    super.setUp();

    poolManager = new MockPoolManager(owner);

    feeController = new V4FeeController(address(poolManager), address(assetSink));

    vm.prank(owner);
    poolManager.setProtocolFeeController(address(feeController));

    // Create mock tokens.
    mockCurrency = Currency.wrap(address(mockToken));
    mockNative = CurrencyLibrary.ADDRESS_ZERO;

    // Mint mock tokens to mock pool manager.
    mockToken.mint(address(poolManager), INITIAL_TOKEN_AMOUNT);
    vm.deal(address(poolManager), INITIAL_NATIVE_AMOUNT);

    // Create mock protocolFees.
    poolManager.setProtocolFeesAccrued(mockCurrency, INITIAL_TOKEN_AMOUNT);
    poolManager.setProtocolFeesAccrued(mockNative, INITIAL_NATIVE_AMOUNT);
  }

  function test_feeController_isSet() public view {
    assertEq(address(poolManager.protocolFeeController()), address(feeController));
  }

  function test_assetSink_isSet() public view {
    assertEq(feeController.feeSink(), address(assetSink));
  }

  function test_collect_full_success() public {
    Currency[] memory currency = new Currency[](1);
    currency[0] = mockCurrency;

    uint256[] memory amountRequested = new uint256[](1);
    amountRequested[0] = 0;

    uint256[] memory amountExpected = new uint256[](1);
    amountExpected[0] = INITIAL_TOKEN_AMOUNT;

    // Anyone can call collect.
    feeController.collect(currency, amountRequested, amountExpected);

    // Phoenix Test Base pre-funds asset sink, and poolManager sends more funds to it
    assertEq(mockCurrency.balanceOf(address(assetSink)), INITIAL_TOKEN_AMOUNT * 2);
    assertEq(mockCurrency.balanceOf(address(poolManager)), 0);
  }

  function test_collect_partial_success() public {
    Currency[] memory currency = new Currency[](1);
    currency[0] = mockCurrency;

    uint256[] memory amountRequested = new uint256[](1);
    amountRequested[0] = 1e18;

    uint256[] memory amountExpected = new uint256[](1);
    amountExpected[0] = 1e18;

    // Anyone can call collect.
    feeController.collect(currency, amountRequested, amountExpected);

    // Phoenix Test Base pre-funds asset sink, and poolManager sends more funds to it
    assertEq(mockCurrency.balanceOf(address(assetSink)), INITIAL_TOKEN_AMOUNT + 1e18);
    assertEq(mockCurrency.balanceOf(address(poolManager)), INITIAL_TOKEN_AMOUNT - 1e18);
  }

  function test_collect_revertsWithAmountCollectedTooLow() public {
    Currency[] memory currency = new Currency[](1);
    currency[0] = mockCurrency;

    /// Request the full amount, expect the full amount to be collected.
    uint256[] memory amountRequested = new uint256[](1);
    amountRequested[0] = 0;
    uint256[] memory amountExpected = new uint256[](1);
    amountExpected[0] = INITIAL_TOKEN_AMOUNT;

    // someone else collects.
    feeController.collect(currency, amountRequested, amountExpected);

    vm.expectRevert(
      abi.encodeWithSelector(
        V4FeeController.AmountCollectedTooLow.selector, 0, INITIAL_TOKEN_AMOUNT
      )
    );
    feeController.collect(currency, amountRequested, amountExpected);
  }

  function test_collect_full_success_native() public {
    Currency[] memory currency = new Currency[](1);
    currency[0] = mockNative;

    uint256[] memory amountRequested = new uint256[](1);
    amountRequested[0] = 0;

    uint256[] memory amountExpected = new uint256[](1);
    amountExpected[0] = INITIAL_NATIVE_AMOUNT;

    // Anyone can call collect.
    feeController.collect(currency, amountRequested, amountExpected);

    // Phoenix Test Base pre-funds asset sink, and poolManager sends more funds to it
    assertEq(mockNative.balanceOf(address(assetSink)), INITIAL_NATIVE_AMOUNT * 2);
    assertEq(mockNative.balanceOf(address(poolManager)), 0);
  }

  function test_collect_partial_success_native() public {
    Currency[] memory currency = new Currency[](1);
    currency[0] = mockNative;

    uint256[] memory amountRequested = new uint256[](1);
    amountRequested[0] = 1e18;

    uint256[] memory amountExpected = new uint256[](1);
    amountExpected[0] = 1e18;

    // Anyone can call collect.
    feeController.collect(currency, amountRequested, amountExpected);

    // Phoenix Test Base pre-funds asset sink, and poolManager sends more funds to it
    assertEq(mockNative.balanceOf(address(assetSink)), INITIAL_NATIVE_AMOUNT + 1e18);
    assertEq(mockNative.balanceOf(address(poolManager)), INITIAL_NATIVE_AMOUNT - 1e18);
  }

  function test_collect_revertsWithAmountCollectedTooLow_native() public {
    Currency[] memory currency = new Currency[](1);
    currency[0] = mockNative;

    /// Request the full amount, expect the full amount to be collected.
    uint256[] memory amountRequested = new uint256[](1);
    amountRequested[0] = 0;
    uint256[] memory amountExpected = new uint256[](1);
    amountExpected[0] = INITIAL_NATIVE_AMOUNT;

    // someone else collects.
    feeController.collect(currency, amountRequested, amountExpected);

    vm.expectRevert(
      abi.encodeWithSelector(
        V4FeeController.AmountCollectedTooLow.selector, 0, INITIAL_NATIVE_AMOUNT
      )
    );
    feeController.collect(currency, amountRequested, amountExpected);
  }
}
