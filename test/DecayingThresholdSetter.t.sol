// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {DecayingThresholdSetter} from "../src/DecayingThresholdSetter.sol";
import {IDecayingThresholdSetter} from "../src/interfaces/IDecayingThresholdSetter.sol";
import {Firepit} from "../src/releasers/Firepit.sol";
import {TokenJar} from "../src/TokenJar.sol";

contract DecayingThresholdSetterTest is Test {
  DecayingThresholdSetter internal setter;
  Firepit internal releaser;
  TokenJar internal tokenJar;
  MockERC20 internal resource;
  MockERC20 internal feeToken;

  address internal governance = makeAddr("governance");
  address internal searcher = makeAddr("searcher");

  uint256 internal constant START = 80_000e18;
  uint256 internal constant FLOOR = 2000e18;
  uint256 internal constant HALF_LIFE = 1 days;
  uint256 internal constant T0 = 1_000_000;

  function setUp() public {
    vm.warp(T0);
    resource = new MockERC20("Resource", "RSC", 18);
    feeToken = new MockERC20("Fee", "FEE", 18);

    // Mirror production: governance owns the releaser and is its threshold setter
    vm.startPrank(governance);
    tokenJar = new TokenJar();
    releaser = new Firepit(address(resource), FLOOR, address(tokenJar));
    tokenJar.setReleaser(address(releaser));
    releaser.setThresholdSetter(governance);
    vm.stopPrank();

    setter = new DecayingThresholdSetter(address(releaser), governance, START, FLOOR, HALF_LIFE);
  }

  function _start() internal {
    vm.startPrank(governance);
    releaser.transferOwnership(address(setter));
    setter.start();
    vm.stopPrank();
  }

  function _thresholdAt(uint256 elapsed) internal returns (uint256) {
    vm.warp(T0 + elapsed);
    return setter.currentThreshold();
  }

  function test_constructor_setsImmutables() public view {
    assertEq(address(setter.RELEASER()), address(releaser));
    assertEq(setter.GOVERNANCE(), governance);
    assertEq(setter.START_THRESHOLD(), START);
    assertEq(setter.FLOOR_THRESHOLD(), FLOOR);
    assertEq(setter.HALF_LIFE(), HALF_LIFE);
    assertEq(setter.startTime(), 0);
  }

  function test_constructor_revertsOnInvalidParameters() public {
    vm.expectRevert(IDecayingThresholdSetter.InvalidParameters.selector);
    new DecayingThresholdSetter(address(0), governance, START, FLOOR, HALF_LIFE);

    vm.expectRevert(IDecayingThresholdSetter.InvalidParameters.selector);
    new DecayingThresholdSetter(address(releaser), address(0), START, FLOOR, HALF_LIFE);

    vm.expectRevert(IDecayingThresholdSetter.InvalidParameters.selector);
    new DecayingThresholdSetter(address(releaser), governance, FLOOR, FLOOR, HALF_LIFE);

    vm.expectRevert(IDecayingThresholdSetter.InvalidParameters.selector);
    new DecayingThresholdSetter(
      address(releaser), governance, uint256(type(uint128).max) + 1, FLOOR, HALF_LIFE
    );

    vm.expectRevert(IDecayingThresholdSetter.InvalidParameters.selector);
    new DecayingThresholdSetter(address(releaser), governance, START, FLOOR, 0);

    vm.expectRevert(IDecayingThresholdSetter.InvalidParameters.selector);
    new DecayingThresholdSetter(
      address(releaser), governance, START, FLOOR, uint256(type(uint64).max) + 1
    );
  }

  function test_constructor_revertsWhenGovernanceNotJarOwner() public {
    vm.expectRevert(IDecayingThresholdSetter.GovernanceNotJarOwner.selector);
    new DecayingThresholdSetter(address(releaser), searcher, START, FLOOR, HALF_LIFE);
  }

  /// @dev New releasers can go straight from their deployer to the setter
  function test_newReleaser_handedStraightToSetter_endsWithGovernance() public {
    address deployer = makeAddr("deployer");
    vm.startPrank(deployer);
    Firepit newReleaser = new Firepit(address(resource), START, address(tokenJar));
    setter = new DecayingThresholdSetter(address(newReleaser), governance, START, FLOOR, HALF_LIFE);
    newReleaser.transferOwnership(address(setter));
    vm.stopPrank();

    vm.startPrank(governance);
    tokenJar.setReleaser(address(newReleaser));
    setter.start();
    vm.stopPrank();
    assertEq(newReleaser.thresholdSetter(), address(setter));

    vm.warp(T0 + 466_560);
    setter.poke();
    assertEq(newReleaser.threshold(), FLOOR);
    assertEq(newReleaser.owner(), governance);
    assertEq(newReleaser.thresholdSetter(), governance);
  }

  function test_currentThreshold_beforeStart_isStartThreshold() public {
    assertEq(setter.currentThreshold(), START);
    vm.warp(T0 + 30 days);
    assertEq(setter.currentThreshold(), START);
  }

  function test_start_takesOverThresholdSetting() public {
    vm.prank(governance);
    releaser.transferOwnership(address(setter));

    vm.expectEmit(address(setter));
    emit IDecayingThresholdSetter.Started(T0, START);
    vm.prank(governance);
    setter.start();

    assertEq(setter.startTime(), T0);
    assertEq(releaser.owner(), address(setter));
    assertEq(releaser.thresholdSetter(), address(setter));
    assertEq(releaser.threshold(), START);
  }

  function test_start_revertsWhenNotGovernance() public {
    vm.prank(governance);
    releaser.transferOwnership(address(setter));

    vm.expectRevert(IDecayingThresholdSetter.Unauthorized.selector);
    vm.prank(searcher);
    setter.start();
  }

  function test_start_revertsWithoutOwnership() public {
    vm.expectRevert("UNAUTHORIZED");
    vm.prank(governance);
    setter.start();
  }

  function test_start_revertsWhenAlreadyStarted() public {
    _start();
    vm.expectRevert(IDecayingThresholdSetter.AlreadyStarted.selector);
    vm.prank(governance);
    setter.start();
  }

  function test_start_revertsUntilJarReleasesThroughReleaser() public {
    vm.startPrank(governance);
    tokenJar.setReleaser(makeAddr("otherReleaser"));
    releaser.transferOwnership(address(setter));

    vm.expectRevert(IDecayingThresholdSetter.ReleaserNotActive.selector);
    setter.start();

    // The decay starts only once the jar releases through the releaser
    vm.warp(T0 + 3 days);
    tokenJar.setReleaser(address(releaser));
    setter.start();
    vm.stopPrank();

    assertEq(setter.startTime(), T0 + 3 days);
    assertEq(setter.currentThreshold(), START);
    assertEq(releaser.threshold(), START);
  }

  /// @dev Expected values are hand-computed from START = 80,000, HALF_LIFE = 1 day, FLOOR = 2,000
  /// and deliberately not derived from the contract's formula
  function test_currentThreshold_curve() public {
    _start();
    assertEq(_thresholdAt(0), 80_000e18);
    assertEq(_thresholdAt(6 hours), 70_000e18);
    assertEq(_thresholdAt(12 hours), 60_000e18);
    assertEq(_thresholdAt(1 days), 40_000e18);
    assertEq(_thresholdAt(36 hours), 30_000e18);
    assertEq(_thresholdAt(2 days), 20_000e18);
    assertEq(_thresholdAt(3 days), 10_000e18);
    assertEq(_thresholdAt(4 days), 5000e18);
    assertEq(_thresholdAt(5 days), 2500e18);
    // 2,500 * (1 - 0.4 / 2) = 2,000: the floor is first reached 5.4 days in
    assertGt(_thresholdAt(466_560 - 1), 2000e18);
    assertEq(_thresholdAt(466_560), 2000e18);
    assertEq(_thresholdAt(6 days), 2000e18);
    assertEq(_thresholdAt(365 days), 2000e18);
    assertEq(_thresholdAt(type(uint64).max), 2000e18);
  }

  /// @dev Exact curve at half a half-life is 80,000 / sqrt(2) = 56,568.54; the interpolation may
  /// only overstate it, and by no more than 6.2%
  function test_currentThreshold_interpolationErrorIsBounded() public {
    _start();
    uint256 interpolated = _thresholdAt(12 hours);
    assertGe(interpolated, 56_568e18);
    assertLe(interpolated, 56_569e18 * 1062 / 1000);
  }

  function test_fuzz_currentThreshold_isMonotonicAndBounded(uint256 t1, uint256 t2) public {
    _start();
    t1 = bound(t1, 0, 30 days);
    t2 = bound(t2, t1, 30 days);

    uint256 a = _thresholdAt(t1);
    uint256 b = _thresholdAt(t2);

    assertGe(a, b);
    assertLe(a, START);
    assertGe(b, FLOOR);
    // Above the floor, stays between the neighbouring whole half-life values
    uint256 halvings = t2 / HALF_LIFE;
    if (b > FLOOR) {
      assertLe(b, START >> halvings);
      assertGe(b, START >> (halvings + 1));
    }
  }

  function test_fuzz_currentThreshold_anyParameters_isMonotonicAndBounded(
    uint256 start,
    uint256 floor,
    uint256 halfLife,
    uint256 t1,
    uint256 t2
  ) public {
    start = bound(start, 1, type(uint128).max);
    floor = bound(floor, 0, start - 1);
    halfLife = bound(halfLife, 1, type(uint64).max);
    t1 = bound(t1, 0, type(uint64).max);
    t2 = bound(t2, t1, type(uint64).max);

    setter = new DecayingThresholdSetter(address(releaser), governance, start, floor, halfLife);
    _start();

    uint256 a = _thresholdAt(t1);
    uint256 b = _thresholdAt(t2);
    assertGe(a, b);
    assertLe(a, start);
    assertGe(b, floor);
  }

  function test_fuzz_currentThreshold_isContinuousAcrossHalfLives(uint8 halvings) public {
    _start();
    uint256 boundary = uint256(bound(halvings, 1, 5)) * HALF_LIFE;
    uint256 before = _thresholdAt(boundary - 1);
    uint256 atBoundary = _thresholdAt(boundary);
    assertGe(before, atBoundary);
    // One second before the boundary is within one second's worth of decay of the boundary value
    assertLe(before - atBoundary, atBoundary / HALF_LIFE + 1);
  }

  function test_poke_revertsBeforeStart() public {
    vm.expectRevert(IDecayingThresholdSetter.NotStarted.selector);
    setter.poke();
  }

  function test_poke_writesCurrentThreshold() public {
    _start();
    vm.warp(T0 + 1 days);

    vm.expectEmit(address(setter));
    emit IDecayingThresholdSetter.ThresholdUpdated(40_000e18);
    vm.prank(searcher);
    assertEq(setter.poke(), 40_000e18);
    assertEq(releaser.threshold(), 40_000e18);
  }

  function test_poke_justAboveFloor_keepsControl() public {
    _start();
    vm.warp(T0 + 466_560 - 1);
    assertGt(setter.poke(), FLOOR);
    assertFalse(setter.controlReturned());
    assertEq(releaser.owner(), address(setter));
    assertEq(releaser.thresholdSetter(), address(setter));
  }

  function test_poke_atFloor_writesFloorAndReturnsControl() public {
    _start();
    vm.warp(T0 + 466_560);

    vm.expectEmit(address(setter));
    emit IDecayingThresholdSetter.ThresholdUpdated(FLOOR);
    vm.expectEmit(address(setter));
    emit IDecayingThresholdSetter.ControlReturned(true);
    vm.prank(searcher);
    assertEq(setter.poke(), FLOOR);

    assertTrue(setter.controlReturned());
    assertEq(releaser.threshold(), FLOOR);
    assertEq(releaser.thresholdSetter(), governance);
    assertEq(releaser.owner(), governance);
  }

  function test_poke_afterFloor_writesFloorAndReturnsControl() public {
    _start();
    vm.warp(T0 + 30 days);
    assertEq(setter.poke(), FLOOR);

    assertTrue(setter.controlReturned());
    assertEq(releaser.threshold(), FLOOR);
    assertEq(releaser.thresholdSetter(), governance);
    assertEq(releaser.owner(), governance);
  }

  function test_poke_revertsAfterPokeAtFloor() public {
    _start();
    vm.warp(T0 + 30 days);
    setter.poke();

    vm.expectRevert(IDecayingThresholdSetter.ControlAlreadyReturned.selector);
    setter.poke();
  }

  function test_poke_revertsAfterFinalize() public {
    _start();
    vm.warp(T0 + 30 days);
    setter.finalize();

    vm.expectRevert(IDecayingThresholdSetter.ControlAlreadyReturned.selector);
    setter.poke();
  }

  function test_finalize_revertsBeforeStart() public {
    vm.expectRevert(IDecayingThresholdSetter.NotStarted.selector);
    setter.finalize();
  }

  function test_finalize_revertsBeforeFloor() public {
    _start();
    vm.warp(T0 + 466_560 - 1);
    vm.expectRevert(IDecayingThresholdSetter.DecayNotComplete.selector);
    setter.finalize();
  }

  function test_finalize_returnsControlToGovernance() public {
    _start();
    vm.warp(T0 + 466_560);

    vm.expectEmit(address(setter));
    emit IDecayingThresholdSetter.ControlReturned(true);
    vm.prank(searcher);
    setter.finalize();

    assertTrue(setter.controlReturned());
    assertEq(releaser.threshold(), FLOOR);
    assertEq(releaser.thresholdSetter(), governance);
    assertEq(releaser.owner(), governance);

    // Governance can use both roles again
    vm.startPrank(governance);
    releaser.setThreshold(3000e18);
    releaser.setThresholdSetter(searcher);
    vm.stopPrank();
    assertEq(releaser.threshold(), 3000e18);
    assertEq(releaser.thresholdSetter(), searcher);
  }

  function test_finalize_revertsWhenCalledTwice() public {
    _start();
    vm.warp(T0 + 30 days);
    setter.finalize();

    vm.expectRevert(IDecayingThresholdSetter.ControlAlreadyReturned.selector);
    setter.finalize();
  }

  function test_finalize_revertsAfterPokeAtFloor() public {
    _start();
    vm.warp(T0 + 30 days);
    setter.poke();

    vm.expectRevert(IDecayingThresholdSetter.ControlAlreadyReturned.selector);
    setter.finalize();
  }

  function test_reclaim_revertsAfterControlReturned() public {
    _start();
    vm.warp(T0 + 30 days);
    setter.poke();

    vm.expectRevert(IDecayingThresholdSetter.ControlAlreadyReturned.selector);
    vm.prank(governance);
    setter.reclaim();
  }

  function test_start_revertsAfterReclaim() public {
    vm.startPrank(governance);
    releaser.transferOwnership(address(setter));
    setter.reclaim();

    vm.expectRevert(IDecayingThresholdSetter.ControlAlreadyReturned.selector);
    setter.start();
    vm.stopPrank();
  }

  function test_reclaim_revertsWhenNotGovernance() public {
    _start();
    vm.expectRevert(IDecayingThresholdSetter.Unauthorized.selector);
    vm.prank(searcher);
    setter.reclaim();
  }

  function test_reclaim_midDecay_returnsControlAndKeepsThreshold() public {
    _start();
    vm.warp(T0 + 1 days);
    setter.poke();

    vm.expectEmit(address(setter));
    emit IDecayingThresholdSetter.ControlReturned(false);
    vm.prank(governance);
    setter.reclaim();

    assertEq(releaser.threshold(), 40_000e18);
    assertEq(releaser.thresholdSetter(), governance);
    assertEq(releaser.owner(), governance);

    vm.expectRevert(IDecayingThresholdSetter.ControlAlreadyReturned.selector);
    setter.poke();
  }

  function test_reclaim_beforeStart_returnsOwnership() public {
    vm.prank(governance);
    releaser.transferOwnership(address(setter));

    vm.prank(governance);
    setter.reclaim();

    assertEq(releaser.owner(), governance);
    assertEq(releaser.thresholdSetter(), governance);
    assertEq(releaser.threshold(), FLOOR);
  }

  function test_integration_releaseAtDecayedThreshold() public {
    feeToken.mint(address(tokenJar), 1_000_000e18);
    vm.deal(address(tokenJar), 10 ether);
    resource.mint(searcher, START);
    Currency[] memory assets = new Currency[](2);
    assets[0] = Currency.wrap(address(feeToken));
    assets[1] = CurrencyLibrary.ADDRESS_ZERO;

    _start();
    vm.warp(T0 + 2 days);

    vm.startPrank(searcher);
    resource.approve(address(releaser), type(uint256).max);
    // Without a poke the releaser still charges the last written, higher threshold
    assertEq(releaser.threshold(), START);
    setter.poke();
    releaser.release(releaser.nonce(), assets, searcher);
    vm.stopPrank();

    assertEq(resource.balanceOf(address(0xdead)), 20_000e18);
    assertEq(resource.balanceOf(searcher), START - 20_000e18);
    assertEq(feeToken.balanceOf(searcher), 1_000_000e18);
    assertEq(searcher.balance, 10 ether);
    assertEq(releaser.nonce(), 1);

    // A later release pays the floor; the poke that writes it also returns control to governance
    feeToken.mint(address(tokenJar), 1e18);
    vm.warp(T0 + 30 days);
    vm.startPrank(searcher);
    setter.poke();
    releaser.release(releaser.nonce(), assets, searcher);
    vm.stopPrank();
    assertEq(resource.balanceOf(address(0xdead)), 22_000e18);
    assertEq(releaser.owner(), governance);
    assertEq(releaser.thresholdSetter(), governance);

    // After the hand-back searchers release directly at the floor without poking
    feeToken.mint(address(tokenJar), 1e18);
    vm.startPrank(searcher);
    releaser.release(releaser.nonce(), assets, searcher);
    vm.stopPrank();
    assertEq(resource.balanceOf(address(0xdead)), 24_000e18);
  }
}
