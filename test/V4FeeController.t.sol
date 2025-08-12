// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

import {V4FeeController} from "src/feeControllers/V4FeeController.sol";
import {MockPoolManager} from "./mocks/MockPoolManager.sol";
import {PhoenixTestBase} from "./utils/PhoenixTestBase.sol";

contract TestV4FeeController is PhoenixTestBase {
  MockPoolManager poolManager;
  V4FeeController feeController;

  Currency mockNative;
  Currency mockCurrency;

  PoolKey poolKey;

  function setUp() public override {
    super.setUp();

    poolManager = new MockPoolManager(owner);

    feeController = new V4FeeController(address(poolManager), address(assetSink), owner);

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

    poolKey = PoolKey({
      currency0: mockNative,
      currency1: mockCurrency,
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(address(0))
    });

    poolManager.mockInitialize(poolKey);
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

    assertEq(mockCurrency.balanceOf(address(assetSink)), INITIAL_TOKEN_AMOUNT);
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

    assertEq(mockCurrency.balanceOf(address(assetSink)), 1e18);
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

  function test_setMerkleRoot_revertsWithInvalidCaller() public {
    vm.expectRevert(abi.encode("UNAUTHORIZED"));
    feeController.setMerkleRoot(bytes32(0));
  }

  function test_setMerkleRoot_revertsWithInvalidCaller_fuzz(address caller) public {
    vm.assume(caller != owner);
    vm.startPrank(caller);
    vm.expectRevert(abi.encode("UNAUTHORIZED"));
    feeController.setMerkleRoot(bytes32(uint256(40)));
  }

  function test_setMerkleRoot_success() public {
    assertEq(feeController.merkleRoot(), bytes32(uint256(0)));
    vm.prank(owner);
    feeController.setMerkleRoot(bytes32(uint256(40)));

    assertEq(feeController.merkleRoot(), bytes32(uint256(40)));
  }

  function test_setMerkleRoot_success_fuzz(bytes32 merkleRoot) public {
    assertEq(feeController.merkleRoot(), bytes32(uint256(0)));
    vm.prank(owner);
    feeController.setMerkleRoot(merkleRoot);
    assertEq(feeController.merkleRoot(), merkleRoot);
  }

  function test_setMerkleRoot_revertsWithInvalidProof() public {
    vm.prank(owner);
    feeController.setMerkleRoot(bytes32(uint256(40)));

    vm.expectRevert(V4FeeController.InvalidProof.selector);
    feeController.triggerFeeUpdate(poolKey, 100, new bytes32[](0));
  }

  function test_triggerFeeUpdate_withValidMerkleProof() public {
    uint24 targetFee = 1000; // 0.1% - max fee

    // Generate leaf nodes.
    bytes32 targetLeaf = keccak256(abi.encode(poolKey, targetFee));
    bytes32 dummyLeaf = keccak256(abi.encode("dummy"));

    bytes32 merkleRoot =
      targetLeaf < dummyLeaf ? _hashPair(targetLeaf, dummyLeaf) : _hashPair(dummyLeaf, targetLeaf);

    // Set the merkle root
    vm.prank(owner);
    feeController.setMerkleRoot(merkleRoot);

    bytes32[] memory proof = new bytes32[](1);
    proof[0] = dummyLeaf;

    feeController.triggerFeeUpdate(poolKey, targetFee, proof);

    assertEq(poolManager.getProtocolFee(poolKey.toId()), targetFee);
  }

  function test_triggerFeeUpdate_withValidMerkleProof_differentPool() public {
    PoolKey memory pool2 = PoolKey({
      currency0: mockNative,
      currency1: mockCurrency,
      fee: 500,
      tickSpacing: 10,
      hooks: IHooks(address(0))
    });

    poolManager.mockInitialize(pool2);

    uint24 protocolFee1 = 1000;
    uint24 protocolFee2 = 500;

    // Generate leaf nodes.
    bytes32 leaf1 = keccak256(abi.encode(poolKey, protocolFee1));
    bytes32 leaf2 = keccak256(abi.encode(pool2, protocolFee2));

    bytes32 merkleRoot = leaf1 < leaf2 ? _hashPair(leaf1, leaf2) : _hashPair(leaf2, leaf1);

    vm.prank(owner);
    feeController.setMerkleRoot(merkleRoot);

    // Generate proof for pool2
    bytes32[] memory proof2 = new bytes32[](1);
    proof2[0] = leaf1;

    feeController.triggerFeeUpdate(pool2, protocolFee2, proof2);

    assertEq(poolManager.getProtocolFee(pool2.toId()), protocolFee2);
    // Assert that the fee for the other pool is not updated.
    assertEq(poolManager.getProtocolFee(poolKey.toId()), 0);
  }

  /// @dev Helper function to hash two nodes in merkle tree
  function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
    return keccak256(abi.encodePacked(a, b));
  }
}
