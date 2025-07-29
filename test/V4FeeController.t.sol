// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {V4FeeController} from "src/feeControllers/V4FeeController.sol";
import {AssetSink} from "src/AssetSink.sol";
import {MockPoolManager} from "./mocks/MockPoolManager.sol";

contract TestV4FeeController is Test {
  MockPoolManager poolManager;
  V4FeeController feeController;
  address owner;
  AssetSink assetSink;
  Currency mockToken;
  Currency mockNative;

  uint256 public constant INITIAL_TOKEN_AMOUNT = 15e18;
  uint256 public constant INITIAL_NATIVE_AMOUNT = 2e18;

  function setUp() public {
    owner = makeAddr("owner");

    poolManager = new MockPoolManager(owner);

    assetSink = new AssetSink(owner);
    feeController = new V4FeeController(address(poolManager), address(assetSink));

    vm.prank(owner);
    poolManager.setProtocolFeeController(address(feeController));

    // Create mock tokens.
    MockERC20 mock = new MockERC20("MockToken", "MTK", 18);
    mockToken = Currency.wrap(address(mock));
    mockNative = CurrencyLibrary.ADDRESS_ZERO;

    // Mint mock tokens to mock pool manager.
    mock.mint(address(poolManager), INITIAL_TOKEN_AMOUNT);
    vm.deal(address(poolManager), INITIAL_NATIVE_AMOUNT);

    // Create mock protocolFees.
    poolManager.setProtocolFeesAccrued(mockToken, INITIAL_TOKEN_AMOUNT);
    poolManager.setProtocolFeesAccrued(mockNative, INITIAL_NATIVE_AMOUNT);
  }

  function test_feeController_isSet() public view {
    assertEq(address(poolManager.protocolFeeController()), address(feeController));
  }

  function test_collect_full_success() public {
    Currency[] memory currency = new Currency[](1);
    currency[0] = mockToken;

    uint256[] memory amountRequested = new uint256[](1);
    amountRequested[0] = 0;

    uint256[] memory amountExpected = new uint256[](1);
    amountExpected[0] = INITIAL_TOKEN_AMOUNT;

    // Anyone can call collect.
    feeController.collect(currency, amountRequested, amountExpected);

    assertEq(mockToken.balanceOf(address(assetSink)), INITIAL_TOKEN_AMOUNT);
    assertEq(mockToken.balanceOf(address(poolManager)), 0);
  }

  function test_collect_partial_success() public {
    Currency[] memory currency = new Currency[](1);
    currency[0] = mockToken;

    uint256[] memory amountRequested = new uint256[](1);
    amountRequested[0] = 1e18;

    uint256[] memory amountExpected = new uint256[](1);
    amountExpected[0] = 1e18;

    // Anyone can call collect.
    feeController.collect(currency, amountRequested, amountExpected);

    assertEq(mockToken.balanceOf(address(assetSink)), 1e18);
    assertEq(mockToken.balanceOf(address(poolManager)), INITIAL_TOKEN_AMOUNT - 1e18);
  }

  function test_collect_revertsWithAmountCollectedTooLow() public {
    Currency[] memory currency = new Currency[](1);
    currency[0] = mockToken;

    /// Request the full amount, expect the full amount to be collected.
    uint256[] memory amountRequested = new uint256[](1);
    amountRequested[0] = 0;
    uint256[] memory amountExpected = new uint256[](1);
    amountExpected[0] = 15e18;

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

    assertEq(mockNative.balanceOf(address(assetSink)), INITIAL_NATIVE_AMOUNT);
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

    assertEq(mockNative.balanceOf(address(assetSink)), 1e18);
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
