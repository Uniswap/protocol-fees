// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {FeeDripper} from "../src/feeAdapters/FeeDripper.sol";
import {IFeeDripper} from "../src/interfaces/IFeeDripper.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract FeeDripperTest is Test {
  using CurrencyLibrary for Currency;

  FeeDripper public feeDripper;
  address public tokenJar = makeAddr("tokenJar");
  address public owner = makeAddr("owner");

  ERC20Mock public erc20Currency;

  function setUp() public {
    vm.prank(owner);
    feeDripper = new FeeDripper(tokenJar);
    vm.deal(address(this), type(uint256).max);
    erc20Currency = new ERC20Mock();
  }

  function _deal(address to, uint256 amount, bool useNativeCurrency) internal {
    if (useNativeCurrency) _dealETH(to, amount);
    else _dealERC20(to, amount);
  }

  function _dealETH(address to, uint256 amount) internal {
    (bool success,) = address(to).call{value: amount}("");
    require(success, "ETH transfer failed");
  }

  function _dealERC20(address to, uint256 amount) internal {
    erc20Currency.mint(to, amount);
  }

  function _currency(bool useNativeCurrency) internal view returns (Currency) {
    return useNativeCurrency ? Currency.wrap(address(0)) : Currency.wrap(address(erc20Currency));
  }

  function _releaseSettings() internal view returns (uint16 window, uint16 windowResetBps) {
    return feeDripper.releaseSettings();
  }

  function _releaseWindow() internal view returns (uint16) {
    (uint16 window,) = _releaseSettings();
    return window;
  }

  function _halfWindow() internal view returns (uint256) {
    return uint256(_releaseWindow()) / 2;
  }

  // ============ Constructor ============

  function test_constructor_revertsOnZeroTokenJar() public {
    vm.expectRevert(IFeeDripper.InvalidTokenJar.selector);
    new FeeDripper(address(0));
  }

  function test_constructor_setsImmutables() public view {
    assertEq(feeDripper.TOKEN_JAR(), tokenJar);
    assertEq(feeDripper.owner(), owner);
    (uint16 window, uint16 windowResetBps) = _releaseSettings();
    assertEq(window, 2000);
    assertEq(windowResetBps, 50);
  }

  // ============ setReleaseSettings ============

  function test_setReleaseSettings_revertsNotOwner(uint16 _newReleaseWindow, uint16 _windowResetBps)
    public
  {
    address notOwner = makeAddr("notOwner");
    vm.expectRevert("UNAUTHORIZED");
    vm.prank(notOwner);
    feeDripper.setReleaseSettings(_newReleaseWindow, _windowResetBps);
  }

  function test_setReleaseSettings_revertsOnZeroWindow(uint16 _windowResetBps) public {
    vm.prank(owner);
    vm.expectRevert(IFeeDripper.InvalidReleaseWindow.selector);
    feeDripper.setReleaseSettings(0, _windowResetBps);
  }

  function test_setReleaseSettings_revertsOnWindowResetBpsAboveBps(
    uint16 _newReleaseWindow,
    uint16 _windowResetBps
  ) public {
    _newReleaseWindow = uint16(bound(_newReleaseWindow, 1, type(uint16).max));
    _windowResetBps = uint16(bound(_windowResetBps, feeDripper.BPS() + 1, type(uint16).max));

    vm.prank(owner);
    vm.expectRevert(IFeeDripper.InvalidWindowResetBps.selector);
    feeDripper.setReleaseSettings(_newReleaseWindow, _windowResetBps);
  }

  function test_setReleaseSettings_succeeds(uint16 _newReleaseWindow, uint16 _windowResetBps)
    public
  {
    _newReleaseWindow = uint16(bound(_newReleaseWindow, 1, type(uint16).max));
    _windowResetBps = uint16(bound(_windowResetBps, 0, feeDripper.BPS()));

    vm.prank(owner);
    vm.expectEmit(true, true, true, true);
    emit IFeeDripper.ReleaseSettingsSet(_newReleaseWindow, _windowResetBps);
    feeDripper.setReleaseSettings(_newReleaseWindow, _windowResetBps);
    (uint16 window, uint16 windowResetBps) = _releaseSettings();
    assertEq(window, _newReleaseWindow);
    assertEq(windowResetBps, _windowResetBps);
  }

  // ============ drip ============

  function test_drip_firstDrip(uint128 _amount, bool _useNativeCurrency) public {
    _amount = uint128(bound(_amount, _releaseWindow(), type(uint128).max));

    Currency currency = _currency(_useNativeCurrency);
    _deal(address(feeDripper), _amount, _useNativeCurrency);

    uint16 window = _releaseWindow();
    uint160 expectedRate = uint160(uint256(_amount) / window);
    uint48 expectedEnd = uint48(block.number + window);

    vm.expectEmit(true, true, true, true);
    emit IFeeDripper.DripUpdated(Currency.unwrap(currency), expectedEnd, expectedRate);
    feeDripper.drip(currency);

    (uint160 rate, uint48 endBlock, uint48 latestBlock) = feeDripper.drips(currency);
    assertEq(rate, expectedRate);
    assertEq(endBlock, expectedEnd);
    assertEq(latestBlock, block.number);
  }

  function test_drip_releasesAccruedAndKeepsWindowWhenNoNewDeposits(bool _useNativeCurrency)
    public
  {
    Currency currency = _currency(_useNativeCurrency);
    _deal(address(feeDripper), 1e18, _useNativeCurrency);
    feeDripper.drip(currency);

    (uint160 rate, uint48 endBlockBefore,) = feeDripper.drips(currency);

    // Advance halfway
    uint256 halfWindow = _halfWindow();
    vm.roll(block.number + halfWindow);
    uint256 expectedReleased = uint256(rate) * halfWindow;

    feeDripper.drip(currency);

    // TokenJar should have received the accrued amount
    uint256 jarBalance = _useNativeCurrency ? tokenJar.balance : erc20Currency.balanceOf(tokenJar);
    assertEq(jarBalance, expectedReleased);

    // Window should be kept because no new deposits were made.
    (, uint48 endBlock, uint48 latestBlock) = feeDripper.drips(currency);
    assertEq(latestBlock, block.number);
    assertEq(endBlock, endBlockBefore);
  }

  function test_drip_afterWindowExpired(bool _useNativeCurrency) public {
    Currency currency = _currency(_useNativeCurrency);
    _deal(address(feeDripper), 1e18, _useNativeCurrency);
    feeDripper.drip(currency);

    // Advance past the window
    vm.roll(block.number + _releaseWindow() + 1);
    feeDripper.drip(currency);

    // All tokens should be in tokenJar (minus dust)
    uint256 jarBalance = _useNativeCurrency ? tokenJar.balance : erc20Currency.balanceOf(tokenJar);
    assertApproxEqAbs(jarBalance, 1e18, _releaseWindow());
  }

  function test_drip_dustFlush(bool _useNativeCurrency) public {
    Currency currency = _currency(_useNativeCurrency);
    uint256 dustAmount = _releaseWindow() - 1;
    _deal(address(feeDripper), dustAmount, _useNativeCurrency);

    feeDripper.drip(currency);

    // Dust should be flushed immediately
    uint256 jarBalance = _useNativeCurrency ? tokenJar.balance : erc20Currency.balanceOf(tokenJar);
    assertEq(jarBalance, dustAmount);

    // Rate should be zero
    (uint160 rate,,) = feeDripper.drips(currency);
    assertEq(rate, 0);
  }

  function test_drip_capsAtUint160Max() public {
    Currency currency = Currency.wrap(address(erc20Currency));
    uint256 excess = 1e18;
    uint256 total = uint256(type(uint160).max) + excess;
    erc20Currency.mint(address(feeDripper), total);

    uint16 window = _releaseWindow();
    uint160 expectedRate = uint160(uint256(type(uint160).max) / window);

    feeDripper.drip(currency);

    (uint160 rate, uint48 endBlock,) = feeDripper.drips(currency);
    assertEq(rate, expectedRate, "rate should be based on capped balance");
    assertEq(endBlock, uint48(block.number + window));
    assertEq(erc20Currency.balanceOf(address(feeDripper)), total);

    // release mid-window
    uint256 halfWindow = _halfWindow();
    vm.roll(block.number + halfWindow);
    feeDripper.release(currency);

    uint256 expectedReleasedMidWindow = uint256(expectedRate) * halfWindow;
    assertEq(erc20Currency.balanceOf(tokenJar), expectedReleasedMidWindow);

    // drip again after the window — picks up leftover (excess + integer division dust)
    vm.roll(block.number + window + 1);
    feeDripper.drip(currency);

    uint256 leftover = uint256(type(uint160).max) - uint256(expectedRate) * window + excess;
    uint160 expectedLeftoverRate = uint160(leftover / window);

    (uint160 rateAfter, uint48 endBlockAfter,) = feeDripper.drips(currency);
    assertEq(rateAfter, expectedLeftoverRate);
    assertEq(endBlockAfter, uint48(block.number + window));
    assertEq(
      erc20Currency.balanceOf(tokenJar),
      expectedReleasedMidWindow + uint256(expectedRate) * (window - halfWindow)
    );
  }

  // ============ release ============

  function test_release_midWindow(bool _useNativeCurrency) public {
    Currency currency = _currency(_useNativeCurrency);
    _deal(address(feeDripper), 1e18, _useNativeCurrency);
    feeDripper.drip(currency);

    (uint160 rate, uint48 endBlock,) = feeDripper.drips(currency);

    uint256 halfWindow = _halfWindow();
    vm.roll(block.number + halfWindow);
    uint256 expectedReleased = uint256(rate) * halfWindow;

    feeDripper.release(currency);

    uint256 jarBalance = _useNativeCurrency ? tokenJar.balance : erc20Currency.balanceOf(tokenJar);
    assertEq(jarBalance, expectedReleased);

    // Window should NOT be reset
    (, uint48 newEndBlock,) = feeDripper.drips(currency);
    assertEq(newEndBlock, endBlock);
  }

  function test_release_doesNotResetWindow(bool _useNativeCurrency) public {
    Currency currency = _currency(_useNativeCurrency);
    _deal(address(feeDripper), 1e18, _useNativeCurrency);
    feeDripper.drip(currency);

    (, uint48 originalEnd,) = feeDripper.drips(currency);
    (uint160 originalRate,,) = feeDripper.drips(currency);

    vm.roll(block.number + 100);
    feeDripper.release(currency);

    (uint160 rate, uint48 endBlock,) = feeDripper.drips(currency);
    assertEq(endBlock, originalEnd);
    assertEq(rate, originalRate);
  }

  function test_release_afterWindowExpired_noUnderflow(bool _useNativeCurrency) public {
    Currency currency = _currency(_useNativeCurrency);
    _deal(address(feeDripper), 1e18, _useNativeCurrency);
    feeDripper.drip(currency);

    // Advance past the window
    vm.roll(block.number + _releaseWindow() * 2);
    feeDripper.release(currency);

    // latestReleaseBlock should be capped at endReleaseBlock
    (, uint48 endBlock, uint48 latestBlock) = feeDripper.drips(currency);
    assertEq(latestBlock, endBlock);

    // Calling again should not revert
    vm.roll(block.number + 100);
    feeDripper.release(currency);
  }

  function test_release_beforeAnyDrip_noOp(bool _useNativeCurrency) public {
    Currency currency = _currency(_useNativeCurrency);
    _deal(address(feeDripper), 1e18, _useNativeCurrency);

    // release without prior drip — no window set, nothing to release
    feeDripper.release(currency);

    uint256 jarBalance = _useNativeCurrency ? tokenJar.balance : erc20Currency.balanceOf(tokenJar);
    // Balance >= releaseWindow so no dust flush, rate is 0, nothing released
    assertEq(jarBalance, 0);
  }

  function test_release_beforeAnyDrip_dustFlushed() public {
    Currency currency = Currency.wrap(address(erc20Currency));
    uint256 dustAmount = _releaseWindow() - 1;
    erc20Currency.mint(address(feeDripper), dustAmount);

    // release before any drip — dust should be flushed
    feeDripper.release(currency);

    assertEq(erc20Currency.balanceOf(tokenJar), dustAmount);
  }

  function test_release_multipleReleasesFullyDrain(bool _useNativeCurrency) public {
    Currency currency = _currency(_useNativeCurrency);
    _deal(address(feeDripper), 1e18, _useNativeCurrency);
    feeDripper.drip(currency);

    uint16 window = _releaseWindow();

    // Release every 100 blocks
    for (uint256 i = 0; i < window / 100; i++) {
      vm.roll(block.number + 100);
      feeDripper.release(currency);
    }

    // Roll past end for final release
    vm.roll(block.number + 200);
    feeDripper.release(currency);

    uint256 jarBalance = _useNativeCurrency ? tokenJar.balance : erc20Currency.balanceOf(tokenJar);
    assertApproxEqAbs(jarBalance, 1e18, _releaseWindow());
  }

  // ============ release does not incorporate new deposits ============

  function test_release_doesNotIncorporateNewDeposits(bool _useNativeCurrency) public {
    Currency currency = _currency(_useNativeCurrency);
    _deal(address(feeDripper), 1e18, _useNativeCurrency);
    feeDripper.drip(currency);

    (uint160 rateBefore,,) = feeDripper.drips(currency);

    // Add more tokens
    _deal(address(feeDripper), 1e18, _useNativeCurrency);

    vm.roll(block.number + 100);
    feeDripper.release(currency);

    // Rate should be unchanged — new deposit not incorporated
    (uint160 rateAfter,,) = feeDripper.drips(currency);
    assertEq(rateAfter, rateBefore);
  }

  function test_drip_incorporatesNewDeposits(bool _useNativeCurrency) public {
    Currency currency = _currency(_useNativeCurrency);
    _deal(address(feeDripper), 1e18, _useNativeCurrency);
    feeDripper.drip(currency);

    (uint160 rateBefore,,) = feeDripper.drips(currency);

    // Add more tokens
    _deal(address(feeDripper), 1e18, _useNativeCurrency);

    vm.roll(block.number + 100);
    feeDripper.drip(currency);

    // Rate should increase — new deposit incorporated
    (uint160 rateAfter,,) = feeDripper.drips(currency);
    assertGt(rateAfter, rateBefore);
  }

  // ============ Currency independence ============

  function test_currenciesAreIndependent() public {
    Currency ethCurrency = Currency.wrap(address(0));
    Currency erc20 = Currency.wrap(address(erc20Currency));

    _deal(address(feeDripper), 1e18, true);
    _deal(address(feeDripper), 2e18, false);

    feeDripper.drip(ethCurrency);
    feeDripper.drip(erc20);

    (uint160 ethRate,,) = feeDripper.drips(ethCurrency);
    (uint160 erc20Rate,,) = feeDripper.drips(erc20);

    // Rates should reflect their respective balances
    assertEq(ethRate, uint160(1e18 / _releaseWindow()));
    assertEq(erc20Rate, uint160(2e18 / _releaseWindow()));
  }

  // ============ Dust ============

  function test_dust_neverRestartsWindow() public {
    Currency currency = Currency.wrap(address(erc20Currency));

    // Deposit an amount that doesn't divide evenly by releaseWindow
    uint256 amount = 1e18 + 999;
    erc20Currency.mint(address(feeDripper), amount);
    feeDripper.drip(currency);

    // Roll past the window
    vm.roll(block.number + _releaseWindow() + 1);
    feeDripper.drip(currency);

    // Everything should be in tokenJar
    assertEq(erc20Currency.balanceOf(tokenJar), amount);

    // Rate should be zero — dust didn't establish a new window
    (uint160 rate,,) = feeDripper.drips(currency);
    assertEq(rate, 0);
  }

  // ============ Linear release ============

  function test_release_isLinear(uint128 _feeAmount, bool _useNativeCurrency) public {
    _feeAmount = uint128(bound(_feeAmount, 1e6, type(uint128).max));

    Currency currency = _currency(_useNativeCurrency);
    _deal(address(feeDripper), _feeAmount, _useNativeCurrency);
    feeDripper.drip(currency);

    uint256 snapshotId = vm.snapshot();
    uint16 window = _releaseWindow();

    // Release per-block
    uint256 totalReleasedPerBlock = 0;
    for (uint256 i = 0; i < window; i++) {
      vm.roll(block.number + 1);
      uint256 before = _useNativeCurrency ? tokenJar.balance : erc20Currency.balanceOf(tokenJar);
      feeDripper.release(currency);
      uint256 after_ = _useNativeCurrency ? tokenJar.balance : erc20Currency.balanceOf(tokenJar);
      totalReleasedPerBlock += (after_ - before);
    }

    vm.revertTo(snapshotId);

    // Release all at once
    vm.roll(block.number + window);
    feeDripper.release(currency);
    uint256 totalReleasedAtOnce =
      _useNativeCurrency ? tokenJar.balance : erc20Currency.balanceOf(tokenJar);

    assertEq(totalReleasedPerBlock, totalReleasedAtOnce, "per-block vs at-once should match");
  }

  // ============ Same block interactions ============

  function test_sameBLock_releaseThenDrip(bool _useNativeCurrency) public {
    Currency currency = _currency(_useNativeCurrency);
    _deal(address(feeDripper), 1e18, _useNativeCurrency);
    feeDripper.drip(currency);

    uint256 halfWindow = _halfWindow();
    vm.roll(block.number + halfWindow);

    // Release first, then drip in same block
    feeDripper.release(currency);
    feeDripper.drip(currency);

    // Should not double-release — second call sees blocksPassed=0
    uint256 jarBalance = _useNativeCurrency ? tokenJar.balance : erc20Currency.balanceOf(tokenJar);

    // Released exactly half-window blocks worth.
    uint256 expectedRelease = uint256(1e18 / _releaseWindow()) * halfWindow;
    assertEq(jarBalance, expectedRelease);
  }

  function test_sameBlock_doubleDrip(bool _useNativeCurrency) public {
    Currency currency = _currency(_useNativeCurrency);
    _deal(address(feeDripper), 1e18, _useNativeCurrency);
    feeDripper.drip(currency);

    uint256 halfWindow = _halfWindow();
    vm.roll(block.number + halfWindow);

    feeDripper.drip(currency);
    feeDripper.drip(currency); // second drip in same block

    // Should not double-release
    uint256 jarBalance = _useNativeCurrency ? tokenJar.balance : erc20Currency.balanceOf(tokenJar);
    uint256 expectedRelease = uint256(1e18 / _releaseWindow()) * halfWindow;
    assertEq(jarBalance, expectedRelease);
  }

  // ============ Griefing scenario ============

  function test_griefing_smallDepositDoesNotResetWindow() public {
    Currency currency = Currency.wrap(address(erc20Currency));
    erc20Currency.mint(address(feeDripper), 1e18);
    feeDripper.drip(currency);

    (, uint48 originalEnd,) = feeDripper.drips(currency);

    // Attacker sends small amount and calls drip mid-window
    vm.roll(block.number + _halfWindow());
    erc20Currency.mint(address(feeDripper), 1000);
    feeDripper.drip(currency);

    (, uint48 newEnd,) = feeDripper.drips(currency);
    // Window was NOT reset because the deposit is below the bps threshold.
    assertEq(newEnd, originalEnd);
  }

  function test_griefing_largeDepositResetsWindow() public {
    Currency currency = Currency.wrap(address(erc20Currency));
    erc20Currency.mint(address(feeDripper), 1e18);
    feeDripper.drip(currency);

    (uint160 rate, uint48 endBlock, uint48 latestBlock) = feeDripper.drips(currency);
    uint256 previousBalance = uint256(endBlock - latestBlock) * rate;
    (, uint48 originalEnd,) = feeDripper.drips(currency);
    (uint16 window, uint16 windowResetBps) = _releaseSettings();

    vm.roll(block.number + _halfWindow());

    // previousBalance is computed from stored stream state. Deposit just above threshold ratio.
    uint256 largeDeposit = (previousBalance * windowResetBps) / feeDripper.BPS() + 1;
    erc20Currency.mint(address(feeDripper), largeDeposit);
    feeDripper.drip(currency);

    (, uint48 newEnd,) = feeDripper.drips(currency);
    assertGt(newEnd, originalEnd);
    assertEq(newEnd, uint48(block.number + window));
  }

  function test_griefing_releaseDoesNotResetWindow() public {
    Currency currency = Currency.wrap(address(erc20Currency));
    erc20Currency.mint(address(feeDripper), 1e18);
    feeDripper.drip(currency);

    (, uint48 originalEnd,) = feeDripper.drips(currency);

    // Attacker sends small amount and calls release mid-window
    vm.roll(block.number + _halfWindow());
    erc20Currency.mint(address(feeDripper), 1000);
    feeDripper.release(currency);

    (, uint48 newEnd,) = feeDripper.drips(currency);
    // Window was NOT reset
    assertEq(newEnd, originalEnd);
  }

  function test_drip_windowResetBpsZero_alwaysResetsWindow() public {
    Currency currency = Currency.wrap(address(erc20Currency));
    uint16 window = _releaseWindow();

    vm.prank(owner);
    feeDripper.setReleaseSettings(window, 0);

    erc20Currency.mint(address(feeDripper), 1e18);
    feeDripper.drip(currency);
    (, uint48 originalEnd,) = feeDripper.drips(currency);

    vm.roll(block.number + _halfWindow());
    // No new deposit, but bps=0 should still force a full reset.
    feeDripper.drip(currency);

    (, uint48 newEnd,) = feeDripper.drips(currency);
    assertGt(newEnd, originalEnd);
    assertEq(newEnd, uint48(block.number + window));
  }

  // ============ Gas snapshots ============

  /// forge-config: default.isolate = true
  /// forge-config: ci.isolate = true
  function test_drip_erc20_gas() public {
    Currency currency = Currency.wrap(address(erc20Currency));
    deal(address(erc20Currency), address(feeDripper), 1e18);
    feeDripper.drip(currency);
    vm.snapshotGasLastCall("drip_erc20_first");

    vm.roll(block.number + _halfWindow());
    feeDripper.drip(currency);
    vm.snapshotGasLastCall("drip_erc20_midWindow");
  }

  /// forge-config: default.isolate = true
  /// forge-config: ci.isolate = true
  function test_drip_nativeCurrency_gas() public {
    Currency currency = Currency.wrap(address(0));
    _dealETH(address(feeDripper), 1e18);
    feeDripper.drip(currency);
    vm.snapshotGasLastCall("drip_nativeCurrency_first");

    vm.roll(block.number + _halfWindow());
    feeDripper.drip(currency);
    vm.snapshotGasLastCall("drip_nativeCurrency_midWindow");
  }

  /// forge-config: default.isolate = true
  /// forge-config: ci.isolate = true
  function test_release_erc20_gas() public {
    Currency currency = Currency.wrap(address(erc20Currency));
    deal(address(erc20Currency), address(feeDripper), 1e18);
    feeDripper.drip(currency);

    vm.roll(block.number + _halfWindow());
    feeDripper.release(currency);
    vm.snapshotGasLastCall("release_erc20_midWindow");
  }

  /// forge-config: default.isolate = true
  /// forge-config: ci.isolate = true
  function test_release_nativeCurrency_gas() public {
    Currency currency = Currency.wrap(address(0));
    _dealETH(address(feeDripper), 1e18);
    feeDripper.drip(currency);

    vm.roll(block.number + _halfWindow());
    feeDripper.release(currency);
    vm.snapshotGasLastCall("release_nativeCurrency_midWindow");
  }

  function test_drip_thresholdBoundary_equalBpsResetsWindow() public {
    Currency currency = Currency.wrap(address(erc20Currency));
    erc20Currency.mint(address(feeDripper), 1e18);
    feeDripper.drip(currency);

    (, uint48 originalEnd,) = feeDripper.drips(currency);
    (uint16 window, uint16 windowResetBps) = _releaseSettings();
    vm.roll(block.number + _halfWindow());

    // Equality should reset because contract keeps old window only when ratio is strictly smaller.
    uint256 equalDeposit = (uint256(1e18) * windowResetBps) / feeDripper.BPS();
    erc20Currency.mint(address(feeDripper), equalDeposit);
    feeDripper.drip(currency);

    (, uint48 newEnd,) = feeDripper.drips(currency);
    assertGt(newEnd, originalEnd);
    assertEq(newEnd, uint48(block.number + window));
  }

  function test_drip_previousBalanceZero_midWindow_noDivisionByZero() public {
    Currency currency = Currency.wrap(address(erc20Currency));
    uint16 window = _releaseWindow();
    uint256 dustAmount = window - 1;
    erc20Currency.mint(address(feeDripper), dustAmount);

    // First drip flushes all dust, leaving terminal state for this block.
    feeDripper.drip(currency);
    (uint160 rate, uint48 endBlock, uint48 latestBlock) = feeDripper.drips(currency);
    assertEq(rate, 0);
    assertEq(endBlock, block.number);
    assertEq(latestBlock, block.number);

    vm.roll(block.number + 1);
    // Should not revert when previousBalance == 0 and there is no active drip.
    feeDripper.drip(currency);
  }

  // ============ Dust flush via release() mid-window ============

  function test_release_dustFlushMidWindow_doesNotBrickCurrency() public {
    Currency currency = Currency.wrap(address(erc20Currency));
    uint16 window = _releaseWindow();

    // Deposit in [window, window*2) so perBlockRate = 1 (low rate).
    uint256 deposit = uint256(window) + 500;
    erc20Currency.mint(address(feeDripper), deposit);
    feeDripper.drip(currency);

    (uint160 rate,,) = feeDripper.drips(currency);
    assertEq(rate, 1);

    // Roll to where remaining balance < releaseWindow (triggers dust flush).
    uint256 blocksToFlush = deposit - window + 1;
    vm.roll(block.number + blocksToFlush);
    feeDripper.release(currency);

    // All tokens flushed to jar
    assertEq(erc20Currency.balanceOf(address(feeDripper)), 0);
    assertEq(erc20Currency.balanceOf(tokenJar), deposit);

    // Rate should be zeroed by the fix — prevents bricked currency
    (uint160 rateAfter,,) = feeDripper.drips(currency);
    assertEq(rateAfter, 0, "perBlockRate should be zeroed after dust flush");

    // Subsequent calls must NOT revert (would underflow without the fix)
    vm.roll(block.number + 100);
    feeDripper.release(currency);
    feeDripper.drip(currency);

    // New deposit starts a fresh drip schedule
    erc20Currency.mint(address(feeDripper), 1e18);
    feeDripper.drip(currency);

    (uint160 recoveredRate, uint48 newEnd,) = feeDripper.drips(currency);
    assertGt(recoveredRate, 0, "should start a new drip after recovery deposit");
    assertEq(newEnd, uint48(block.number + window));
  }
}
