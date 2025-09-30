// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {PhoenixTestBase} from "./utils/PhoenixTestBase.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {MerkleProof} from "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import {
  UniswapV3FactoryDeployer,
  IUniswapV3Factory
} from "briefcase/deployers/v3-core/UniswapV3FactoryDeployer.sol";
import {Merkle} from "murky/src/Merkle.sol";
import {V3FeeController, IV3FeeController} from "../src/feeControllers/V3FeeController.sol";
import {IOwned} from "../src/interfaces/base/IOwned.sol";

contract V3FeeControllerTest is PhoenixTestBase {
  using MerkleProof for bytes32[];

  IUniswapV3Factory public factory;

  IV3FeeController public feeController;

  uint160 public constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

  address pool;
  address pool1;

  Merkle merkle;

  uint256 slot = 3;

  PoolObject poolObject0;
  PoolObject poolObject1;

  address feeSetter;

  struct ProtocolFees {
    uint128 token0;
    uint128 token1;
  }

  struct PoolObject {
    address pool;
    uint24 fee;
    /// token1 | token0
    uint8 protocolFee;
  }

  function setUp() public override {
    super.setUp();

    factory = UniswapV3FactoryDeployer.deploy();
    /// Prank the old owner so we can just use our internal owner.
    vm.prank(factory.owner());
    factory.setOwner(owner);

    vm.startPrank(owner);
    feeController = new V3FeeController(address(factory), address(assetSink));
    feeController.setFeeSetter(owner);
    factory.setOwner(address(feeController));
    vm.stopPrank();

    /// Store fee tiers.
    feeController.storeFeeTier(500);
    feeController.storeFeeTier(3000);
    feeController.storeFeeTier(10_000);

    feeSetter = feeController.feeSetter();

    // Create pool.
    pool = factory.createPool(address(mockToken), address(mockToken1), 3000);
    pool1 = factory.createPool(address(mockToken), address(mockToken1), 10_000);
    IUniswapV3Pool(pool).initialize(SQRT_PRICE_1_1);
    IUniswapV3Pool(pool1).initialize(SQRT_PRICE_1_1);

    poolObject0 = PoolObject({pool: pool, fee: 3000, protocolFee: 0});
    poolObject1 = PoolObject({pool: pool1, fee: 10_000, protocolFee: 0});

    // Mint tokens.
    mockToken.mint(address(pool), INITIAL_TOKEN_AMOUNT);
    mockToken1.mint(address(pool), INITIAL_TOKEN_AMOUNT);

    merkle = new Merkle();
  }

  function test_feeController_isOwner() public view {
    assertEq(address(factory.owner()), address(feeController));
  }

  function test_assetSink_isSet() public view {
    assertEq(feeController.ASSET_SINK(), address(assetSink));
  }

  function test_enableFeeAmount() public {
    uint24 newTier = 750;
    vm.prank(owner);
    feeController.enableFeeAmount(750, 1);

    uint24 _tier = feeController.feeTiers(3);
    assertEq(_tier, newTier);
  }

  function test_collect_full_success() public {
    uint128 amount0 = 10e18;
    uint128 amount1 = 11e18;

    address token0 =
      address(mockToken) < address(mockToken1) ? address(mockToken) : address(mockToken1);
    address token1 =
      address(mockToken) < address(mockToken1) ? address(mockToken1) : address(mockToken);

    _mockSetProtocolFees(amount0, amount1);

    IV3FeeController.CollectParams[] memory collectParams = new IV3FeeController.CollectParams[](1);
    collectParams[0] = IV3FeeController.CollectParams({
      pool: pool,
      amount0Requested: amount0,
      amount1Requested: amount1
    });

    uint256 balanceBefore = MockERC20(token0).balanceOf(address(assetSink));
    uint256 balanceBefore1 = MockERC20(token1).balanceOf(address(assetSink));

    // Anyone can call collect.
    IV3FeeController.Collected[] memory collected = feeController.collect(collectParams);

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
    vm.expectRevert(IV3FeeController.Unauthorized.selector);
    feeController.setMerkleRoot(bytes32(0));
  }

  function test_setMerkleRoot_revertsWithInvalidCaller_fuzz(address caller) public {
    vm.assume(caller != owner);
    vm.startPrank(caller);
    vm.expectRevert(IV3FeeController.Unauthorized.selector);
    feeController.setMerkleRoot(bytes32(uint256(40)));
  }

  function test_setMerkleRoot_success() public {
    assertEq(feeController.merkleRoot(), bytes32(uint256(0)));
    vm.prank(feeSetter);
    feeController.setMerkleRoot(bytes32(uint256(40)));

    assertEq(feeController.merkleRoot(), bytes32(uint256(40)));
  }

  function test_setMerkleRoot_success_fuzz(bytes32 merkleRoot) public {
    assertEq(feeController.merkleRoot(), bytes32(uint256(0)));
    vm.prank(feeSetter);
    feeController.setMerkleRoot(merkleRoot);
    assertEq(feeController.merkleRoot(), merkleRoot);
  }

  function test_setMerkleRoot_revertsWithInvalidProof() public {
    vm.prank(feeSetter);
    feeController.setMerkleRoot(bytes32(uint256(40)));

    vm.expectRevert(IV3FeeController.InvalidProof.selector);
    feeController.triggerFeeUpdate(pool, new bytes32[](0));
  }

  function test_triggerFeeUpdate_withValidMerkleProof() public {
    uint8 fee0 = 5;
    uint8 fee1 = 10;

    poolObject0.protocolFee = fee1 << 4 | fee0;

    // Generate leaf nodes.
    address dummyPool = poolObject1.pool;
    bytes32 targetLeaf = _hashLeaf(poolObject0.pool);
    bytes32 dummyLeaf = _hashLeaf(dummyPool);

    bytes32[] memory leaves = new bytes32[](2);
    leaves[0] = targetLeaf;
    leaves[1] = dummyLeaf;

    bytes32 merkleRoot = merkle.getRoot(leaves);

    // Set the merkle root
    vm.startPrank(feeSetter);
    feeController.setMerkleRoot(merkleRoot);
    feeController.setDefaultFeeByFeeTier(poolObject0.fee, poolObject0.protocolFee);
    vm.stopPrank();

    bytes32[] memory proof = merkle.getProof(leaves, 0);

    feeController.triggerFeeUpdate(poolObject0.pool, proof);
    (,,,,, uint8 poolFees,) = IUniswapV3Pool(poolObject0.pool).slot0();
    assertEq(poolFees, poolObject0.protocolFee);
  }

  function test_triggerFeeUpdate_byPair_withValidMerkleProof() public {
    uint8 fee0 = 5;
    uint8 fee1 = 10;
    poolObject0.protocolFee = fee1 << 4 | fee0;

    poolObject1.protocolFee = 4 << 4 | 8;

    // Generate leaf nodes.
    address dummyPool = poolObject1.pool;
    bytes32 targetLeaf = _hashLeaf(poolObject0.pool);
    bytes32 dummyLeaf = _hashLeaf(dummyPool);

    bytes32[] memory leaves = new bytes32[](2);
    leaves[0] = targetLeaf;
    leaves[1] = dummyLeaf;

    bytes32 merkleRoot = merkle.getRoot(leaves);

    // Set the merkle root
    vm.startPrank(feeSetter);
    feeController.setMerkleRoot(merkleRoot);
    feeController.setDefaultFeeByFeeTier(poolObject0.fee, poolObject0.protocolFee); // 0.30% pool
    feeController.setDefaultFeeByFeeTier(poolObject1.fee, poolObject1.protocolFee); // 1.00% pool
    vm.stopPrank();

    bytes32[] memory proof = merkle.getProof(leaves, 0);

    (address _token0, address _token1) = address(mockToken) < address(mockToken1)
      ? (address(mockToken), address(mockToken1))
      : (address(mockToken1), address(mockToken));
    feeController.triggerFeeUpdate(_token0, _token1, proof);

    (,,,,, uint8 poolFees,) = IUniswapV3Pool(poolObject0.pool).slot0();
    assertEq(poolFees, poolObject0.protocolFee);
    (,,,,, uint8 protocolFees1,) = IUniswapV3Pool(poolObject1.pool).slot0();
    assertEq(protocolFees1, poolObject1.protocolFee);
  }

  function test_triggerFeeUpdate_withValidMerkleProof_differentPool() public {
    uint8 protocolFee2 = 5;

    /// Save the protocol fee for poolObject1. Token0 and token1 have the same protocol fee.
    poolObject1.protocolFee = protocolFee2 << 4 | protocolFee2;

    // Generate leaf nodes.
    bytes32 leaf1 = _hashLeaf(poolObject0.pool);
    bytes32 leaf2 = _hashLeaf(poolObject1.pool);

    bytes32[] memory leaves = new bytes32[](2);
    leaves[0] = leaf1;
    leaves[1] = leaf2;

    bytes32 merkleRoot = merkle.getRoot(leaves);

    vm.startPrank(feeSetter);
    feeController.setMerkleRoot(merkleRoot);
    feeController.setDefaultFeeByFeeTier(poolObject1.fee, poolObject1.protocolFee);
    vm.stopPrank();

    // Generate proof for pool1
    bytes32[] memory proof2 = merkle.getProof(leaves, 1);

    feeController.triggerFeeUpdate(poolObject1.pool, proof2);

    (,,,,, uint8 protocolFees,) = IUniswapV3Pool(poolObject1.pool).slot0();
    assertEq(protocolFees, poolObject1.protocolFee);

    // Assert that the fee for the other pool is not updated.
    (,,,,, uint8 protocolFees0,) = IUniswapV3Pool(poolObject0.pool).slot0();
    assertEq(protocolFees0, 0);
  }

  function test_triggerFeeUpdate_multiPool_success() public {
    address pool2 = factory.createPool(address(mockToken), address(mockToken1), uint24(500));
    IUniswapV3Pool(pool2).initialize(SQRT_PRICE_1_1);

    poolObject0.protocolFee = 10 << 4 | 8;
    poolObject1.protocolFee = 9 << 4 | 7;
    PoolObject memory poolObject2 = PoolObject({pool: pool2, fee: 500, protocolFee: 8 << 4 | 5});

    bytes32[] memory leaves = new bytes32[](3);

    leaves[0] = _hashLeaf(poolObject0.pool);
    leaves[1] = _hashLeaf(poolObject1.pool);
    leaves[2] = _hashLeaf(poolObject2.pool);

    bytes32 merkleRoot = merkle.getRoot(leaves);

    vm.startPrank(feeSetter);
    feeController.setMerkleRoot(merkleRoot);
    feeController.setDefaultFeeByFeeTier(poolObject0.fee, poolObject0.protocolFee);
    feeController.setDefaultFeeByFeeTier(poolObject1.fee, poolObject1.protocolFee);
    feeController.setDefaultFeeByFeeTier(poolObject2.fee, poolObject2.protocolFee);
    vm.stopPrank();

    bytes32[] memory proof0 = merkle.getProof(leaves, 0);

    /// Trigger the fee update for pool0.
    feeController.triggerFeeUpdate(poolObject0.pool, proof0);

    /// Assert that the fee for pool0 is updated, and that the other pools are not updated.
    assertEq(_getProtocolFees(poolObject0.pool), poolObject0.protocolFee);
    assertEq(_getProtocolFees(poolObject1.pool), 0);
    assertEq(_getProtocolFees(poolObject2.pool), 0);

    /// Trigger the fee updates for the rest of the pools.
    bytes32[] memory proof1 = merkle.getProof(leaves, 1);
    bytes32[] memory proof2 = merkle.getProof(leaves, 2);

    feeController.triggerFeeUpdate(poolObject1.pool, proof1);
    feeController.triggerFeeUpdate(poolObject2.pool, proof2);

    /// Assert that the fees for all the pools are updated.
    assertEq(_getProtocolFees(poolObject1.pool), poolObject1.protocolFee);
    assertEq(_getProtocolFees(poolObject2.pool), poolObject2.protocolFee);
  }

  function test_triggerFeeUpdate_9000Pool_success_gas() public {
    address[] memory pools = new address[](9000);
    bytes32[] memory leaves = new bytes32[](9000);

    uint24 feeTier = 500;
    uint8 protocolFee = 10 << 4 | 9;
    for (uint256 i = 0; i < 9000; i++) {
      MockERC20 token_i = new MockERC20("Token", "TKN", 18);
      address pool_i = factory.createPool(address(token_i), address(mockToken1), feeTier);
      IUniswapV3Pool(pool_i).initialize(SQRT_PRICE_1_1);
      pools[i] = pool_i;
      leaves[i] = _hashLeaf(pool_i);
    }

    bytes32 merkleRoot = merkle.getRoot(leaves);

    vm.startPrank(feeSetter);
    feeController.setMerkleRoot(merkleRoot);
    feeController.setDefaultFeeByFeeTier(feeTier, protocolFee);
    vm.stopPrank();

    bytes32[] memory proof0 = merkle.getProof(leaves, 0);
    bytes32[] memory proof4500 = merkle.getProof(leaves, 4500);
    bytes32[] memory proof8999 = merkle.getProof(leaves, 8999);

    /// Trigger the fee update for pool at index 0.
    feeController.triggerFeeUpdate(pools[0], proof0);
    vm.snapshotGasLastCall("triggerFeeUpdate_0");

    /// Trigger the fee update for pool at index 4500.
    feeController.triggerFeeUpdate(pools[4500], proof4500);
    vm.snapshotGasLastCall("triggerFeeUpdate_4500");

    /// Trigger the fee update for pool at index 8999.
    feeController.triggerFeeUpdate(pools[8999], proof8999);
    vm.snapshotGasLastCall("triggerFeeUpdate_8999");

    assertEq(_getProtocolFees(pools[0]), protocolFee);
    assertEq(_getProtocolFees(pools[4500]), protocolFee);
    assertEq(_getProtocolFees(pools[8999]), protocolFee);
    /// Not all pools' fees are updated.
    assertEq(_getProtocolFees(pools[1]), 0);
  }

  function test_batchTriggerFeeUpdate_9000Pool_success_gas() public {
    address[] memory pools = new address[](9000);
    bytes32[] memory leaves = new bytes32[](9000);

    IV3FeeController.Pair[] memory pairs = new IV3FeeController.Pair[](9000);

    uint24 feeTier = 3000;
    uint8 protocolFee = 7 << 4 | 6;

    for (uint256 i = 0; i < 9000; i++) {
      MockERC20 token_i = new MockERC20("Token", "TKN", 18);
      address pool_i = factory.createPool(address(token_i), address(mockToken1), feeTier);
      IUniswapV3Pool(pool_i).initialize(SQRT_PRICE_1_1);
      pools[i] = pool_i;
      leaves[i] = _hashLeaf(pool_i);
      pairs[i] = _toPair(address(token_i), address(mockToken1));
    }

    bool[] memory proofFlags = new bool[](leaves.length - 1);
    for (uint256 i = 0; i < leaves.length - 1; i++) {
      proofFlags[i] = true;
    }

    bytes32 root = MerkleProof.processMultiProof(new bytes32[](0), proofFlags, leaves);

    vm.startPrank(feeSetter);
    feeController.setMerkleRoot(root);
    feeController.setDefaultFeeByFeeTier(feeTier, protocolFee);
    vm.stopPrank();

    /// Batch trigger all fee updates.
    feeController.batchTriggerFeeUpdate(pairs, new bytes32[](0), proofFlags);
    vm.snapshotGasLastCall("batchTriggerFeeUpdate_allLeaves");

    assertEq(_getProtocolFees(pools[0]), protocolFee);
    assertEq(_getProtocolFees(pools[8999]), protocolFee);
  }

  function test_fuzz_triggerFeeUpdate_revertsInvalidProtocolFee(
    address invalidToken0,
    address invalidToken1
  ) public {
    /// Valid tokens in the merkle tree:
    address token0_0 = IUniswapV3Pool(poolObject0.pool).token0();
    address token1_0 = IUniswapV3Pool(poolObject0.pool).token1();
    address token0_1 = IUniswapV3Pool(poolObject1.pool).token0();
    address token1_1 = IUniswapV3Pool(poolObject1.pool).token1();

    // Make sure we can create a pool from the two tokens. These are V3 Factory constraints.
    vm.assume(invalidToken0 != address(0));
    vm.assume(invalidToken1 != address(0));
    vm.assume(invalidToken0 != invalidToken1);

    /// Make sure that the invalid tokens are not in the merkle tree pairs.
    vm.assume(invalidToken0 != token0_0);
    vm.assume(invalidToken1 != token1_0);
    vm.assume(invalidToken0 != token0_1);
    vm.assume(invalidToken1 != token1_1);

    // Create a new pool from those tokens.
    address invalidPool = factory.createPool(invalidToken0, invalidToken1, 3000);
    IUniswapV3Pool(invalidPool).initialize(SQRT_PRICE_1_1);

    /// The leaf node is generated from the valid pool's pair.
    bytes32 leaf = _hashLeaf(poolObject0.pool);
    bytes32 dummyLeaf = _hashLeaf(poolObject1.pool);

    bytes32[] memory leaves = new bytes32[](2);
    leaves[0] = leaf;
    leaves[1] = dummyLeaf;

    bytes32 merkleRoot = merkle.getRoot(leaves);

    vm.prank(feeSetter);
    feeController.setMerkleRoot(merkleRoot);

    bytes32[] memory proof = merkle.getProof(leaves, 0);

    vm.expectRevert();
    feeController.triggerFeeUpdate(invalidPool, proof);
  }

  function test_fuzz_setFeeSetter(address newFeeSetter) public {
    vm.prank(owner);
    feeController.setFeeSetter(newFeeSetter);
    assertEq(feeController.feeSetter(), newFeeSetter);
  }

  function test_fuzz_revert_setFeeSetter(address caller, address newFeeSetter) public {
    vm.assume(caller != IOwned(address(feeController)).owner());

    vm.prank(caller);
    vm.expectRevert("UNAUTHORIZED");
    feeController.setFeeSetter(newFeeSetter);
  }

  function test_setFactoryOwner() public {
    address newOwner = makeAddr("newOwner");
    vm.prank(owner);
    feeController.setFactoryOwner(newOwner);
    assertEq(factory.owner(), newOwner);
  }

  function test_setFactoryOwner_reverts(address caller) public {
    vm.assume(caller != owner);
    vm.prank(caller);
    vm.expectRevert("UNAUTHORIZED");
    feeController.setFactoryOwner(address(0));
  }

  function test_fuzz_setDefaultFeeByFeeTier(uint24 feeTier, uint8 defaultFee) public {
    vm.startPrank(feeController.feeSetter());
    if (factory.feeAmountTickSpacing(feeTier) == 0) {
      vm.expectRevert(IV3FeeController.InvalidFeeTier.selector);
      feeController.setDefaultFeeByFeeTier(feeTier, defaultFee);
    } else {
      feeController.setDefaultFeeByFeeTier(feeTier, defaultFee);
      assertEq(feeController.defaultFees(feeTier), defaultFee);
    }

    vm.stopPrank();
  }

  function test_fuzz_revert_setDefaultFeeByFeeTier(address caller, uint24 feeTier, uint8 defaultFee)
    public
  {
    vm.assume(caller != feeController.feeSetter());

    vm.prank(caller);
    vm.expectRevert(IV3FeeController.Unauthorized.selector);
    feeController.setDefaultFeeByFeeTier(feeTier, defaultFee);
  }

  function test_setDefaultFeeByFeeTier_revertsWithInvalidFeeTier() public {
    vm.prank(feeSetter);
    vm.expectRevert(IV3FeeController.InvalidFeeTier.selector);
    feeController.setDefaultFeeByFeeTier(11_000, 10);
  }

  function _mockSetProtocolFees(uint128 token0, uint128 token1) internal {
    uint256 toSet = uint256(token1) << 128 | uint256(token0);
    vm.store(pool, bytes32(slot), bytes32(toSet));
  }

  function _getProtocolFees(address _pool) internal view returns (uint8 poolFeesPacked) {
    (,,,,, uint8 poolFees,) = IUniswapV3Pool(_pool).slot0();
    return poolFees;
  }

  function _hashLeaf(address _pool) internal view returns (bytes32) {
    return keccak256(
      abi.encode(
        keccak256(abi.encode(IUniswapV3Pool(_pool).token0(), IUniswapV3Pool(_pool).token1()))
      )
    );
  }

  function _toPair(address tokenA, address tokenB)
    internal
    pure
    returns (IV3FeeController.Pair memory)
  {
    if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
    return IV3FeeController.Pair({token0: tokenA, token1: tokenB});
  }
}
