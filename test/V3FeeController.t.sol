// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {PhoenixTestBase} from "./utils/PhoenixTestBase.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {
  UniswapV3FactoryDeployer,
  IUniswapV3Factory
} from "briefcase/deployers/v3-core/UniswapV3FactoryDeployer.sol";
import {Merkle} from "murky/src/Merkle.sol";
import {V3FeeController} from "../src/feeControllers/V3FeeController.sol";

contract V3FeeControllerTest is PhoenixTestBase {
  IUniswapV3Factory public factory;

  V3FeeController public feeController;

  uint160 public constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

  address pool;
  address pool1;

  Merkle merkle;

  uint256 slot = 3;

  struct ProtocolFees {
    uint128 token0;
    uint128 token1;
  }

  function setUp() public override {
    super.setUp();

    factory = UniswapV3FactoryDeployer.deploy();
    vm.prank(factory.owner());
    factory.setOwner(owner);

    feeController = new V3FeeController(address(factory), address(assetSink), factory.owner(), factory.owner());

    /// Transfer ownership to the fee controller.
    vm.prank(factory.owner());
    factory.setOwner(address(feeController));

    // Create pool.
    pool = factory.createPool(address(mockToken), address(mockToken1), 3000);
    pool1 = factory.createPool(address(mockToken), address(mockToken1), 10_000);
    IUniswapV3Pool(pool).initialize(SQRT_PRICE_1_1);
    IUniswapV3Pool(pool1).initialize(SQRT_PRICE_1_1);

    // Mint tokens.
    mockToken.mint(address(pool), INITIAL_TOKEN_AMOUNT);
    mockToken1.mint(address(pool), INITIAL_TOKEN_AMOUNT);

    merkle = new Merkle();
  }

  function test_feeController_isOwner() public {
    assertEq(address(factory.owner()), address(feeController));
  }

  function test_assetSink_isSet() public view {
    assertEq(feeController.FEE_SINK(), address(assetSink));
  }

  function test_collect_full_success() public {
    uint128 amount0 = 10e18;
    uint128 amount1 = 11e18;

    address token0 =
      address(mockToken) < address(mockToken1) ? address(mockToken) : address(mockToken1);
    address token1 =
      address(mockToken) < address(mockToken1) ? address(mockToken1) : address(mockToken);

    _mockSetProtocolFees(amount0, amount1);

    V3FeeController.CollectParams[] memory collectParams = new V3FeeController.CollectParams[](1);
    collectParams[0] = V3FeeController.CollectParams({
      pool: pool,
      amount0Requested: amount0,
      amount1Requested: amount1
    });

    uint256 balanceBefore = MockERC20(token0).balanceOf(address(assetSink));
    uint256 balanceBefore1 = MockERC20(token1).balanceOf(address(assetSink));

    // Anyone can call collect.
    V3FeeController.Collected[] memory collected = feeController.collect(collectParams);

    // Note that 1 wei is left in the pool.
    assertEq(collected[0].amount0Collected, amount0 - 1);
    assertEq(collected[0].amount1Collected, amount1 - 1);

    // Phoenix Test Base pre-funds asset sink, and poolManager sends more funds to it
    assertEq(MockERC20(token0).balanceOf(address(assetSink)), balanceBefore + amount0 - 1);
    assertEq(MockERC20(token1).balanceOf(address(assetSink)), balanceBefore1 + amount1 - 1);
  }

  /// Test spoofed storage setting in UniswapV3Pool.
  function test_protocolFees_set() public {
    (uint128 token0, uint128 token1) = IUniswapV3Pool(pool).protocolFees();
    assertEq(token0, 0);
    assertEq(token1, 0);

    uint128 protocolFee0 = 1e18;
    uint128 protocolFee1 = 3e18;

    _mockSetProtocolFees(protocolFee0, protocolFee1);

    (token0, token1) = IUniswapV3Pool(pool).protocolFees();
    assertEq(token0, protocolFee0);
    assertEq(token1, protocolFee1);
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

    vm.expectRevert(V3FeeController.InvalidProof.selector);
    feeController.triggerFeeUpdate(pool, 10, 10, new bytes32[](0));
  }

  function test_triggerFeeUpdate_withValidMerkleProof() public {
    uint8 fee0 = 5;
    uint8 fee1 = 10;

    // Generate leaf nodes.
    bytes32 targetLeaf = keccak256(abi.encode(pool, fee0, fee1));
    bytes32 dummyLeaf = keccak256(abi.encode("dummy"));

    bytes32[] memory leaves = new bytes32[](2);
    leaves[0] = targetLeaf;
    leaves[1] = dummyLeaf;

    bytes32 merkleRoot = merkle.getRoot(leaves);

    // Set the merkle root
    vm.prank(owner);
    feeController.setMerkleRoot(merkleRoot);

    bytes32[] memory proof = merkle.getProof(leaves, 0);

    feeController.triggerFeeUpdate(pool, fee0, fee1, proof);
    (,,,,, uint8 poolFees,) = IUniswapV3Pool(pool).slot0();
    assertEq(poolFees, fee0 | fee1 << 4);
  }

  function test_triggerFeeUpdate_withValidMerkleProof_differentPool() public {
    uint8 protocolFee = 10;
    uint8 protocolFee2 = 5;

    // Generate leaf nodes.
    bytes32 leaf1 = keccak256(abi.encode(pool, protocolFee, protocolFee));
    bytes32 leaf2 = keccak256(abi.encode(pool1, protocolFee2, protocolFee2));

    bytes32[] memory leaves = new bytes32[](2);
    leaves[0] = leaf1;
    leaves[1] = leaf2;

    bytes32 merkleRoot = merkle.getRoot(leaves);

    vm.prank(owner);
    feeController.setMerkleRoot(merkleRoot);

    // Generate proof for pool1
    bytes32[] memory proof2 = merkle.getProof(leaves, 1);

    feeController.triggerFeeUpdate(pool1, protocolFee2, protocolFee2, proof2);

    (,,,,, uint8 poolFees,) = IUniswapV3Pool(pool1).slot0();
    assertEq(poolFees, protocolFee2 | protocolFee2 << 4);

    // Assert that the fee for the other pool is not updated.
    (,,,,, uint8 poolFees0,) = IUniswapV3Pool(pool).slot0();
    assertEq(poolFees0, 0);
  }

  function test_triggerFeeUpdate_multiPool_success() public {
    address pool2 = factory.createPool(address(mockToken), address(mockToken1), uint24(500));
    IUniswapV3Pool(pool2).initialize(SQRT_PRICE_1_1);

    address[] memory pools = new address[](3);
    pools[0] = pool;
    pools[1] = pool1;
    pools[2] = pool2;

    uint8[] memory fees = new uint8[](3);
    fees[0] = 10;
    fees[1] = 9;
    fees[2] = 8;

    bytes32[] memory leaves = new bytes32[](3);
    for (uint256 i = 0; i < leaves.length; i++) {
      leaves[i] = keccak256(abi.encode(pools[i], fees[i], fees[i]));
    }

    bytes32 merkleRoot = merkle.getRoot(leaves);

    vm.prank(owner);
    feeController.setMerkleRoot(merkleRoot);

    bytes32[] memory proof0 = merkle.getProof(leaves, 0);

    /// Trigger the fee update for pool0.
    feeController.triggerFeeUpdate(pools[0], fees[0], fees[0], proof0);

    /// Assert that the fee for pool0 is updated, and that the other pools are not updated.
    assertEq(_getProtocolFees(pools[0]), fees[0] | fees[0] << 4);
    assertEq(_getProtocolFees(pools[1]), 0);
    assertEq(_getProtocolFees(pools[2]), 0);

    /// Trigger the fee updates for the rest of the pools.

    bytes32[] memory proof1 = merkle.getProof(leaves, 1);
    bytes32[] memory proof2 = merkle.getProof(leaves, 2);

    feeController.triggerFeeUpdate(pools[1], fees[1], fees[1], proof1);
    feeController.triggerFeeUpdate(pools[2], fees[2], fees[2], proof2);

    /// Assert that the fees for all the pools are updated.
    assertEq(_getProtocolFees(pools[1]), fees[1] | fees[1] << 4);
    assertEq(_getProtocolFees(pools[2]), fees[2] | fees[2] << 4);
  }

  function test_fuzz_triggerFeeUpdate_revertsInvalidProtocolFee(uint8 invalidFee) public {
    vm.assume(0 < invalidFee);
    vm.assume(invalidFee < 4 || invalidFee > 10);

    bytes32 leaf = keccak256(abi.encode(pool, invalidFee, invalidFee));
    bytes32 dummyLeaf = keccak256("dummy");

    bytes32[] memory leaves = new bytes32[](2);
    leaves[0] = leaf;
    leaves[1] = dummyLeaf;

    bytes32 merkleRoot = merkle.getRoot(leaves);

    vm.prank(owner);
    feeController.setMerkleRoot(merkleRoot);

    bytes32[] memory proof = merkle.getProof(leaves, 0);

    vm.expectRevert();
    feeController.triggerFeeUpdate(pool, invalidFee, invalidFee, proof);
  }

  function _mockSetProtocolFees(uint128 token0, uint128 token1) internal {
    uint256 toSet = uint256(token1) << 128 | uint256(token0);
    vm.store(pool, bytes32(slot), bytes32(toSet));
  }

  function _getProtocolFees(address _pool) internal returns (uint8 poolFeesPacked) {
    (,,,,, uint8 poolFees,) = IUniswapV3Pool(_pool).slot0();
    return poolFees;
  }
}
