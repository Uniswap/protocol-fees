// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IUniswapV3Factory} from "briefcase/deployers/v3-core/UniswapV3FactoryDeployer.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {MainnetDeployer} from "../script/deployers/MainnetDeployer.sol";
import {ITokenJar} from "../src/interfaces/ITokenJar.sol";
import {IReleaser} from "../src/interfaces/IReleaser.sol";
import {IOwned} from "../src/interfaces/base/IOwned.sol";
import {IV3FeeAdapter} from "../src/interfaces/IV3FeeAdapter.sol";
import {Merkle} from "murky/src/Merkle.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {UnificationProposal} from "../script/04_UnificationProposal.s.sol";

contract ProtocolFeesForkTest is Test {
  using FixedPointMathLib for uint256;

  MainnetDeployer public deployer;
  IUniswapV3Factory public factory;
  IUniswapV2Factory public v2Factory;
  IUniswapV2Router02 public v2Router;

  ITokenJar public tokenJar;
  IReleaser public releaser;
  IV3FeeAdapter public feeAdapter;

  address public owner;
  Merkle merkle;
  address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

  // v3 pools
  address pool0; // USDC-WETH 1 bip pool
  address pool1; // USDC-WETH 5 bip pool
  address pool2; // USDC-WETH 30 bip pool
  address pool3; // USDC-WETH 1% pool

  // WBTC-USDC pools
  address wbtcPool0; // WBTC-USDC 1 bip pool
  address wbtcPool1; // WBTC-USDC 5 bip pool
  address wbtcPool2; // WBTC-USDC 30 bip pool
  address wbtcPool3; // WBTC-USDC 1% pool

  // v2 pair: WETH / USDC
  IUniswapV2Pair pair;

  function setUp() public {
    vm.createSelectFork("mainnet");
    factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    v2Factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    v2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    owner = factory.owner();

    deployer = new MainnetDeployer();
    UnificationProposal proposal = new UnificationProposal();
    proposal.runPranked(deployer);
    tokenJar = deployer.TOKEN_JAR();
    releaser = deployer.RELEASER();
    feeAdapter = deployer.V3_FEE_ADAPTER();

    merkle = new Merkle();

    // USDC-WETH pools
    pool0 = factory.getPool(WETH, USDC, 100); // 1 bip pool
    pool1 = factory.getPool(WETH, USDC, 500); // 5 bip pool
    pool2 = factory.getPool(WETH, USDC, 3000); // 30 bip pool
    pool3 = factory.getPool(WETH, USDC, 10_000); // 1% pool

    // WBTC-USDC pools
    wbtcPool0 = factory.getPool(WBTC, USDC, 100); // 1 bip pool
    wbtcPool1 = factory.getPool(WBTC, USDC, 500); // 5 bip pool
    wbtcPool2 = factory.getPool(WBTC, USDC, 3000); // 30 bip pool
    wbtcPool3 = factory.getPool(WBTC, USDC, 10_000); // 1% pool

    pair = IUniswapV2Pair(v2Factory.getPair(WETH, USDC));

    IERC20(USDC).approve(address(v2Router), type(uint256).max);
    IERC20(WETH).approve(address(v2Router), type(uint256).max);
  }

  function test_enableFeeV3() public {
    assertEq(feeAdapter.feeSetter(), owner);
    // Generate merkle root from leaves
    bytes32 targetLeaf = _hashLeaf(USDC, WETH);
    bytes32 dummyLeaf = _hashLeaf(address(0), address(1));
    bytes32[] memory leaves = new bytes32[](2);
    leaves[0] = targetLeaf;
    leaves[1] = dummyLeaf;
    bytes32 merkleRoot = merkle.getRoot(leaves);

    vm.prank(owner);
    feeAdapter.setMerkleRoot(merkleRoot);

    // Enable fees on the 4 pools
    bytes32[] memory proof = merkle.getProof(leaves, 0);
    feeAdapter.triggerFeeUpdate(USDC, WETH, proof);

    // fees were set correctly, from the Deployer.sol
    (,,,,, uint8 protocolFee,) = IUniswapV3Pool(pool0).slot0();
    assertEq(protocolFee, 4 << 4 | 4);
    (,,,,, protocolFee,) = IUniswapV3Pool(pool1).slot0();
    assertEq(protocolFee, 4 << 4 | 4);
    (,,,,, protocolFee,) = IUniswapV3Pool(pool2).slot0();
    assertEq(protocolFee, 6 << 4 | 6);
    (,,,,, protocolFee,) = IUniswapV3Pool(pool3).slot0();
    assertEq(protocolFee, 6 << 4 | 6);
  }

  function test_enableFeeV3MultiProof() public {
    assertEq(feeAdapter.feeSetter(), owner);

    // Using the real merkle root from the generated merkle tree
    bytes32 merkleRoot = 0x414b3244586a0a8ccde5f69624d8c697705f894f429e2d5adecefddd375d2f58;

    vm.prank(owner);
    feeAdapter.setMerkleRoot(merkleRoot);

    // Setting up the pairs for USDC-WETH and WBTC-USDC
    IV3FeeAdapter.Pair[] memory pairs = new IV3FeeAdapter.Pair[](2);
    pairs[0] = IV3FeeAdapter.Pair({token0: USDC, token1: WETH});
    pairs[1] = IV3FeeAdapter.Pair({token0: WBTC, token1: USDC});

    // Multi-proof elements from the generated proof
    bytes32[] memory proof = new bytes32[](19);

    proof[0] = hex"6491c363f49ce4bb83ce9c2cdd5b56a962c53cf8ad104219ed91385ed1540802";
    proof[1] = hex"ebece2c743a5fbb314dc2776f896d72e2ff67d3a4f129f1757aa5d5ab677e33a";
    proof[2] = hex"900fc66a8b61766ca646f09e7674c9d4afc83f717334111f535080c4eccd6c9c";
    proof[3] = hex"211e83765b6d8e124531eae66c1ee4f9e0570b4c75e9508fd4df802725b5ad4f";
    proof[4] = hex"5e2bf878cd5f31d0f58df92cbb5ca98ce84608ac1199285988142696e13f138d";
    proof[5] = hex"00297a030932b384d55bbdcdcaaa589fcac62f155c3764d27e49d16ec3316227";
    proof[6] = hex"070584a9c964c10b35d9cbd891ae71c5c8c3c4a323a7d4c0ad2dcaea0adb9400";
    proof[7] = hex"baa50bad5c1038ae56de2dd71badc88c1002f85c225a57d35eb6de619334880e";
    proof[8] = hex"13bf26148a62f801302746719a0d2360a06c5e803193847305545f77f4286c39";
    proof[9] = hex"5f8c7d372cb4665567e935966e87020a510746aec6a2939d618c39a1fb3d6628";
    proof[10] = hex"a3c2cb41e9d0a2de1f5c0fe79764073cd124567902b40c6bb637815342d0569b";
    proof[11] = hex"75fed44c10fe53b6b9414e14e8a214c56cd02a0bb5c8c2d948f20a546cc376ca";
    proof[12] = hex"e57a4a98131339fc9734284b6a36e99db186fcbf0640773512a5742c336e8d7f";
    proof[13] = hex"e5fca2152a8d5a7d959aaa133b564fa41e5155dcccabfe17289d887eb2670185";
    proof[14] = hex"f2804f3a9b11e320fabcc68c5c0b4beabdbb43eaaaec7c2a8a2c44818ef3ef29";
    proof[15] = hex"fbe9480f027e8126275f82da9e2fccd453384539a6b48bf811cc853cf2f087f0";
    proof[16] = hex"53e476e913319c5b3714c352ff8975a79548d96e11cdd06c7dd6be975d417c20";
    proof[17] = hex"a3e710526979e9dec0755d7e2357c3ef5ef01f838e0a4345736107cb179fb8a1";
    proof[18] = hex"bc0721000f45dd0c27e8caf9cad20735b833154350d7dc41c2beae6c474f45c3";

    // Proof flags from the generated proof (all false except last one)
    bool[] memory proofFlags = new bool[](20);
    for (uint256 i = 0; i < 20; i++) {
      proofFlags[i] = (i == 19);
    }

    // Enable fees on the pools
    feeAdapter.batchTriggerFeeUpdate(pairs, proof, proofFlags);

    // Verify fees were set correctly for USDC-WETH pools
    (,,,,, uint8 protocolFee,) = IUniswapV3Pool(pool0).slot0();
    assertEq(protocolFee, 4 << 4 | 4);
    (,,,,, protocolFee,) = IUniswapV3Pool(pool1).slot0();
    assertEq(protocolFee, 4 << 4 | 4);
    (,,,,, protocolFee,) = IUniswapV3Pool(pool2).slot0();
    assertEq(protocolFee, 6 << 4 | 6);
    (,,,,, protocolFee,) = IUniswapV3Pool(pool3).slot0();
    assertEq(protocolFee, 6 << 4 | 6);

    // Verify fees were set correctly for WBTC-USDC pools
    (,,,,, protocolFee,) = IUniswapV3Pool(wbtcPool0).slot0();
    assertEq(protocolFee, 4 << 4 | 4);
    (,,,,, protocolFee,) = IUniswapV3Pool(wbtcPool1).slot0();
    assertEq(protocolFee, 4 << 4 | 4);
    (,,,,, protocolFee,) = IUniswapV3Pool(wbtcPool2).slot0();
    assertEq(protocolFee, 6 << 4 | 6);
    (,,,,, protocolFee,) = IUniswapV3Pool(wbtcPool3).slot0();
    assertEq(protocolFee, 6 << 4 | 6);
  }

  function test_enableFeeV2() public {
    assertEq(v2Factory.feeToSetter(), owner);
    vm.prank(owner);
    v2Factory.setFeeTo(address(tokenJar));
    assertEq(v2Factory.feeTo(), address(tokenJar));
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

    // some liquidity is sent to the token jar
    assertGt(pair.balanceOf(address(tokenJar)), 0);
  }

  function test_collectFeeV3() public {
    test_enableFeeV3();

    // swap on the 5 bip pool
    deal(USDC, address(this), 3000e6);
    _exactInSwapV3(pool1, true, 1000e6);
    deal(WETH, address(this), 3e18);
    _exactInSwapV3(pool1, false, 1e18);

    (uint128 token0Pool1, uint128 token1Pool1) = IUniswapV3Pool(pool1).protocolFees();
    assertApproxEqRel(token0Pool1, uint256(1000e6).mulWadDown(0.0005e18) / 4, 0.0001e18);
    assertApproxEqRel(token1Pool1, uint256(1e18).mulWadDown(0.0005e18) / 4, 0.0001e18);

    // swap on 30 bip pool
    _exactInSwapV3(pool2, true, 1000e6);
    _exactInSwapV3(pool2, false, 1e18);
    (uint128 token0Pool2, uint128 token1Pool2) = IUniswapV3Pool(pool2).protocolFees();
    assertApproxEqRel(token0Pool2, uint256(1000e6).mulWadDown(0.003e18) / 6, 0.0001e18);
    assertApproxEqRel(token1Pool2, uint256(1e18).mulWadDown(0.003e18) / 6, 0.0001e18);

    // swap on 1% pool
    _exactInSwapV3(pool3, true, 1000e6);
    _exactInSwapV3(pool3, false, 1e18);
    (uint128 token0Pool3, uint128 token1Pool3) = IUniswapV3Pool(pool3).protocolFees();
    assertApproxEqRel(token0Pool3, uint256(1000e6).mulWadDown(0.01e18) / 6, 0.0001e18);
    assertApproxEqRel(token1Pool3, uint256(1e18).mulWadDown(0.01e18) / 6, 0.0001e18);

    IV3FeeAdapter.CollectParams[] memory params = new IV3FeeAdapter.CollectParams[](3);
    params[0] = IV3FeeAdapter.CollectParams({
      pool: pool1, amount0Requested: type(uint128).max, amount1Requested: type(uint128).max
    });
    params[1] = IV3FeeAdapter.CollectParams({
      pool: pool2, amount0Requested: type(uint128).max, amount1Requested: type(uint128).max
    });
    params[2] = IV3FeeAdapter.CollectParams({
      pool: pool3, amount0Requested: type(uint128).max, amount1Requested: type(uint128).max
    });

    // token jar has no tokens
    assertEq(IERC20(USDC).balanceOf(address(tokenJar)), 0);
    assertEq(IERC20(WETH).balanceOf(address(tokenJar)), 0);
    feeAdapter.collect(params);

    // token jar has collected all fees
    // subtract 3 wei because the v3 pool always leaves 1 wei behind
    assertEq(
      IERC20(USDC).balanceOf(address(tokenJar)), token0Pool1 + token0Pool2 + token0Pool3 - 3 wei
    );
    assertEq(
      IERC20(WETH).balanceOf(address(tokenJar)), token1Pool1 + token1Pool2 + token1Pool3 - 3 wei
    );
  }

  function test_releaseV3(address caller, address recipient) public {
    vm.assume(caller != address(0));
    vm.assume(recipient != address(0) && recipient != address(tokenJar) && recipient != USDC);
    test_collectFeeV3();

    // give the caller some UNI to burn
    deal(deployer.RESOURCE(), address(caller), releaser.threshold());
    assertEq(IERC20(deployer.RESOURCE()).balanceOf(address(caller)), releaser.threshold());

    uint256 balance0Before = IERC20(USDC).balanceOf(recipient);
    uint256 balance1Before = IERC20(WETH).balanceOf(recipient);

    uint256 balance0TokenJarBefore = IERC20(USDC).balanceOf(address(tokenJar));
    uint256 balance1TokenJarBefore = IERC20(WETH).balanceOf(address(tokenJar));

    // release the assets
    uint256 _nonce = releaser.nonce();
    Currency[] memory currencies = new Currency[](2);
    currencies[0] = Currency.wrap(USDC);
    currencies[1] = Currency.wrap(WETH);

    vm.startPrank(caller);
    IERC20(deployer.RESOURCE()).approve(address(releaser), releaser.threshold());
    releaser.release(_nonce, currencies, recipient);
    vm.stopPrank();

    // amounts transferred from the token jar to the recipient
    assertEq(IERC20(USDC).balanceOf(address(tokenJar)), 0);
    assertEq(IERC20(WETH).balanceOf(address(tokenJar)), 0);
    assertEq(IERC20(USDC).balanceOf(recipient) - balance0Before, balance0TokenJarBefore);
    assertEq(IERC20(WETH).balanceOf(recipient) - balance1Before, balance1TokenJarBefore);
  }

  function test_releaseV2V3(address caller, address recipient) public {
    vm.assume(caller != address(0));
    vm.assume(recipient != address(0) && recipient != address(tokenJar) && recipient != USDC);
    test_createV2Fees();
    test_collectFeeV3();

    uint256 pairBalanceBefore = pair.balanceOf(address(tokenJar));

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

    // amounts transferred from the token jar to the recipient
    assertEq(IERC20(USDC).balanceOf(address(tokenJar)), 0);
    assertEq(IERC20(WETH).balanceOf(address(tokenJar)), 0);
    assertEq(pair.balanceOf(address(tokenJar)), 0);
    assertEq(pair.balanceOf(recipient), pairBalanceBefore);
  }

  /// @dev ensure v3 factory owner is recoverable
  function test_undo_v3(address newOwner) public {
    test_releaseV2V3(address(this), address(this));

    vm.prank(owner);
    feeAdapter.setFactoryOwner(newOwner);

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
