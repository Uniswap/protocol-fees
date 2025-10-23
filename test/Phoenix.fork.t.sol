// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {
  UniswapV3FactoryDeployer,
  IUniswapV3Factory
} from "briefcase/deployers/v3-core/UniswapV3FactoryDeployer.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {Deployer} from "../src/Deployer.sol";
import {IAssetSink} from "../src/interfaces/IAssetSink.sol";
import {IReleaser} from "../src/interfaces/IReleaser.sol";
import {IOwned} from "../src/interfaces/base/IOwned.sol";
import {IV3FeeController} from "../src/interfaces/IV3FeeController.sol";
import {Merkle} from "murky/src/Merkle.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";

contract PhoenixForkTest is Test {
  using FixedPointMathLib for uint256;

  Deployer public deployer;
  IUniswapV3Factory public factory;
  IUniswapV2Factory public v2Factory;
  IUniswapV2Router02 public v2Router;

  IAssetSink public assetSink;
  IReleaser public releaser;
  IV3FeeController public feeController;

  address public owner;
  Merkle merkle;
  address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

  // v3 pools
  address pool0; // 1 bip pool
  address pool1; // 5 bip pool
  address pool2; // 30 bip pool
  address pool3; // 1% pool

  // v2 pair: WETH / USDC
  IUniswapV2Pair pair;

  function setUp() public {
    vm.createSelectFork("mainnet");
    factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    v2Factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    v2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    owner = factory.owner();

    deployer = new Deployer();
    assetSink = deployer.ASSET_SINK();
    releaser = deployer.RELEASER();
    feeController = deployer.FEE_CONTROLLER();

    merkle = new Merkle();

    // set the fee controller on the v3 factory
    vm.prank(owner);
    factory.setOwner(address(feeController));

    // assumes governance timelock takes back control of the feeSetter
    vm.prank(owner);
    IFeeToSetter(0x18e433c7Bf8A2E1d0197CE5d8f9AFAda1A771360).setFeeToSetter(owner);

    pool0 = factory.getPool(WETH, USDC, 100); // 1 bip pool
    pool1 = factory.getPool(WETH, USDC, 500); // 5 bip pool
    pool2 = factory.getPool(WETH, USDC, 3000); // 30 bip pool
    pool3 = factory.getPool(WETH, USDC, 10_000); // 1% pool

    pair = IUniswapV2Pair(v2Factory.getPair(WETH, USDC));

    IERC20(USDC).approve(address(v2Router), type(uint256).max);
    IERC20(WETH).approve(address(v2Router), type(uint256).max);
  }

  function test_enableFeeV3() public {
    assertEq(feeController.feeSetter(), owner);

    // Generate merkle root from leaves
    bytes32 targetLeaf = _hashLeaf(USDC, WETH);
    bytes32 dummyLeaf = _hashLeaf(address(0), address(1));
    bytes32[] memory leaves = new bytes32[](2);
    leaves[0] = targetLeaf;
    leaves[1] = dummyLeaf;
    bytes32 merkleRoot = merkle.getRoot(leaves);

    vm.prank(owner);
    feeController.setMerkleRoot(merkleRoot);

    // Enable fees on the 4 pools
    bytes32[] memory proof = merkle.getProof(leaves, 0);
    feeController.triggerFeeUpdate(USDC, WETH, proof);

    // fees were set correctly, from the Deployer.sol
    (,,,,, uint8 protocolFee,) = IUniswapV3Pool(pool0).slot0();
    assertEq(protocolFee, 4 << 4 | 4);
    (,,,,, protocolFee,) = IUniswapV3Pool(pool1).slot0();
    assertEq(protocolFee, 6 << 4 | 6);
    (,,,,, protocolFee,) = IUniswapV3Pool(pool2).slot0();
    assertEq(protocolFee, 8 << 4 | 8);
    (,,,,, protocolFee,) = IUniswapV3Pool(pool3).slot0();
    assertEq(protocolFee, 10 << 4 | 10);
  }

  function test_enableFeeV2() public {
    assertEq(v2Factory.feeToSetter(), owner);
    vm.prank(owner);
    v2Factory.setFeeTo(address(assetSink));
    assertEq(v2Factory.feeTo(), address(assetSink));
  }

  function test_createV2Fees() public {
    test_enableFeeV2();

    // add liquidity
    deal(USDC, address(this), 1_000_000e6);
    deal(WETH, address(this), 1000e18);
    (,, uint256 liquidity) =
      v2Router.addLiquidity(USDC, WETH, 1_000_000e6, 100e18, 0, 0, address(this), block.timestamp);
    assertEq(pair.balanceOf(address(this)), liquidity);

    deal(USDC, address(this), 1000e6);
    _exactInSwapV2(pair, true, 1000e6);

    deal(WETH, address(this), 10e18);
    _exactInSwapV2(pair, false, 10e18);

    // collect fees by withdrawing liquidity
    pair.approve(address(v2Router), liquidity);
    v2Router.removeLiquidity(
      USDC, WETH, pair.balanceOf(address(this)), 0, 0, address(this), block.timestamp
    );

    // some liquidity is sent to the asset sink
    assertGt(pair.balanceOf(address(assetSink)), 0);
  }

  function test_collectFeeV3() public {
    test_enableFeeV3();

    // swap on the 5 bip pool
    deal(USDC, address(this), 3000e6);
    _exactInSwapV3(pool1, true, 1000e6);
    deal(WETH, address(this), 3e18);
    _exactInSwapV3(pool1, false, 1e18);

    (uint128 token0Pool1, uint128 token1Pool1) = IUniswapV3Pool(pool1).protocolFees();
    assertApproxEqRel(token0Pool1, uint256(1000e6).mulWadDown(0.0005e18) / 6, 0.0001e18);
    assertApproxEqRel(token1Pool1, uint256(1e18).mulWadDown(0.0005e18) / 6, 0.0001e18);

    // swap on 30 bip pool
    _exactInSwapV3(pool2, true, 1000e6);
    _exactInSwapV3(pool2, false, 1e18);
    (uint128 token0Pool2, uint128 token1Pool2) = IUniswapV3Pool(pool2).protocolFees();
    assertApproxEqRel(token0Pool2, uint256(1000e6).mulWadDown(0.003e18) / 8, 0.0001e18);
    assertApproxEqRel(token1Pool2, uint256(1e18).mulWadDown(0.003e18) / 8, 0.0001e18);

    // swap on 1% pool
    _exactInSwapV3(pool3, true, 1000e6);
    _exactInSwapV3(pool3, false, 1e18);
    (uint128 token0Pool3, uint128 token1Pool3) = IUniswapV3Pool(pool3).protocolFees();
    assertApproxEqRel(token0Pool3, uint256(1000e6).mulWadDown(0.01e18) / 10, 0.0001e18);
    assertApproxEqRel(token1Pool3, uint256(1e18).mulWadDown(0.01e18) / 10, 0.0001e18);

    IV3FeeController.CollectParams[] memory params = new IV3FeeController.CollectParams[](3);
    params[0] = IV3FeeController.CollectParams({
      pool: pool1, amount0Requested: type(uint128).max, amount1Requested: type(uint128).max
    });
    params[1] = IV3FeeController.CollectParams({
      pool: pool2, amount0Requested: type(uint128).max, amount1Requested: type(uint128).max
    });
    params[2] = IV3FeeController.CollectParams({
      pool: pool3, amount0Requested: type(uint128).max, amount1Requested: type(uint128).max
    });

    // asset sink has no tokens
    assertEq(IERC20(USDC).balanceOf(address(assetSink)), 0);
    assertEq(IERC20(WETH).balanceOf(address(assetSink)), 0);
    feeController.collect(params);

    // asset sink has collected all fees
    // subtract 3 wei because the v3 pool always leaves 1 wei behind
    assertEq(
      IERC20(USDC).balanceOf(address(assetSink)), token0Pool1 + token0Pool2 + token0Pool3 - 3 wei
    );
    assertEq(
      IERC20(WETH).balanceOf(address(assetSink)), token1Pool1 + token1Pool2 + token1Pool3 - 3 wei
    );
  }

  function test_releaseV3(address caller, address recipient) public {
    vm.assume(caller != address(0));
    vm.assume(recipient != address(0));
    test_collectFeeV3();

    // give the caller some UNI to burn
    deal(deployer.RESOURCE(), address(caller), releaser.threshold());
    assertEq(IERC20(deployer.RESOURCE()).balanceOf(address(caller)), releaser.threshold());

    uint256 balance0Before = IERC20(USDC).balanceOf(recipient);
    uint256 balance1Before = IERC20(WETH).balanceOf(recipient);

    uint256 balance0AssetSinkBefore = IERC20(USDC).balanceOf(address(assetSink));
    uint256 balance1AssetSinkBefore = IERC20(WETH).balanceOf(address(assetSink));

    // release the assets
    uint256 _nonce = releaser.nonce();
    Currency[] memory currencies = new Currency[](2);
    currencies[0] = Currency.wrap(USDC);
    currencies[1] = Currency.wrap(WETH);

    vm.startPrank(caller);
    IERC20(deployer.RESOURCE()).approve(address(releaser), releaser.threshold());
    releaser.release(_nonce, currencies, recipient);
    vm.stopPrank();

    // amounts transferred from the asset sink to the recipient
    assertEq(IERC20(USDC).balanceOf(address(assetSink)), 0);
    assertEq(IERC20(WETH).balanceOf(address(assetSink)), 0);
    assertEq(IERC20(USDC).balanceOf(recipient) - balance0Before, balance0AssetSinkBefore);
    assertEq(IERC20(WETH).balanceOf(recipient) - balance1Before, balance1AssetSinkBefore);
  }

  function test_releaseV2V3(address caller, address recipient) public {
    vm.assume(caller != address(0));
    vm.assume(recipient != address(0));
    test_createV2Fees();
    test_collectFeeV3();

    uint256 pairBalanceBefore = pair.balanceOf(address(assetSink));

    // give the caller some UNI to burn
    deal(deployer.RESOURCE(), address(caller), releaser.threshold());
    assertEq(IERC20(deployer.RESOURCE()).balanceOf(address(caller)), releaser.threshold());

    // release the assets
    uint256 _nonce = releaser.nonce();
    Currency[] memory currencies = new Currency[](3);
    currencies[0] = Currency.wrap(USDC);
    currencies[1] = Currency.wrap(WETH);
    currencies[2] = Currency.wrap(address(pair));

    vm.startPrank(caller);
    IERC20(deployer.RESOURCE()).approve(address(releaser), releaser.threshold());
    releaser.release(_nonce, currencies, recipient);
    vm.stopPrank();

    // amounts transferred from the asset sink to the recipient
    assertEq(IERC20(USDC).balanceOf(address(assetSink)), 0);
    assertEq(IERC20(WETH).balanceOf(address(assetSink)), 0);
    assertEq(pair.balanceOf(address(assetSink)), 0);
    assertEq(pair.balanceOf(recipient), pairBalanceBefore);
  }

  /// @dev ensure v3 factory owner is recoverable
  function test_undo_v3(address newOwner) public {
    test_releaseV2V3(address(this), address(this));

    vm.prank(owner);
    feeController.setFactoryOwner(newOwner);

    assertEq(IOwned(address(factory)).owner(), newOwner);
  }

  /// @dev ensures v2 factory feeTo is recoverable
  function test_undo_v2(address newFeeTo) public {
    test_releaseV2V3(address(this), address(this));

    vm.prank(owner);
    v2Factory.setFeeTo(newFeeTo);
    assertEq(v2Factory.feeTo(), newFeeTo);
  }

  // --- Helpers ---

  function _hashLeaf(address token0, address token1) internal pure returns (bytes32) {
    return keccak256(abi.encode(keccak256(abi.encode(token0, token1))));
  }

  function _exactInSwapV3(address pool, bool zeroForOne, uint256 amountIn) internal {
    IUniswapV3Pool(pool)
      .swap(
        address(this),
        zeroForOne,
        int256(amountIn),
        // constants grabbed from v3-core TickMath, pasted here to avoid type conversion in new
        // solidity version
        zeroForOne
          ? 4_295_128_739 + 1
          : 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342 - 1,
        abi.encode(address(this)) // encode the payer
      );
  }

  function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data)
    external
  {
    address user = abi.decode(data, (address));
    if (amount0Delta > 0) {
      IERC20 token = IERC20(IUniswapV3Pool(msg.sender).token0());
      vm.prank(user);
      token.approve(address(this), uint256(amount0Delta));
      token.transferFrom(user, msg.sender, uint256(amount0Delta));
    } else if (amount1Delta > 0) {
      IERC20 token = IERC20(IUniswapV3Pool(msg.sender).token1());
      vm.prank(user);
      token.approve(address(this), uint256(amount1Delta));
      token.transferFrom(user, msg.sender, uint256(amount1Delta));
    }
  }

  function _exactInSwapV2(IUniswapV2Pair _pair, bool zeroForOne, uint256 amountIn) internal {
    address[] memory path = new address[](2);
    path[0] = zeroForOne ? _pair.token0() : _pair.token1();
    path[1] = zeroForOne ? _pair.token1() : _pair.token0();
    v2Router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp);
  }
}

// interface for:
// https://etherscan.io/address/0x18e433c7Bf8A2E1d0197CE5d8f9AFAda1A771360#code
// the current v2Factory.feeToSetter()
interface IFeeToSetter {
  function setFeeToSetter(address) external;
}
