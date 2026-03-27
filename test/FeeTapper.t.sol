// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FeeTapper} from "../src/feeAdapters/FeeTapper.sol";
import {IFeeTapper} from "../src/interfaces/IFeeTapper.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract FeeTapperTest is Test {
  using CurrencyLibrary for Currency;

  FeeTapper public feeTapper;
  address public tokenJar = makeAddr("tokenJar");
  address public owner = makeAddr("owner");

  ERC20Mock public erc20Currency;

  uint24 public constant BPS = 10_000;

  function setUp() public {
    feeTapper = new FeeTapper(tokenJar, owner);
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

  function test_setPerBlockReleaseRate_reverts_notOwner(uint24 _perBlockReleaseRate) public {
    address notOwner = makeAddr("notOwner");
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
    vm.prank(notOwner);
    feeTapper.setReleaseRate(_perBlockReleaseRate);
  }

  function test_setReleaseRate_WhenEqZero() public {
    // it reverts with {ReleaseRateOutOfBounds()}

    vm.prank(owner);
    vm.expectRevert(IFeeTapper.ReleaseRateOutOfBounds.selector);
    feeTapper.setReleaseRate(0);
  }

  function test_setReleaseRate_WhenGtBPS(uint24 _perBlockReleaseRate) public {
    // it reverts with {ReleaseRateOutOfBounds()}

    _perBlockReleaseRate = uint24(bound(_perBlockReleaseRate, BPS + 1, type(uint24).max));

    vm.prank(owner);
    vm.expectRevert(IFeeTapper.ReleaseRateOutOfBounds.selector);
    feeTapper.setReleaseRate(_perBlockReleaseRate);
  }

  function test_setReleaseRate_WhenNotDivisibleByBPS(uint24 _perBlockReleaseRate) public {
    // it reverts with {InvalidReleaseRate()}

    _perBlockReleaseRate = uint24(bound(_perBlockReleaseRate, 1, BPS - 1));
    vm.assume(BPS % _perBlockReleaseRate != 0);

    vm.prank(owner);
    vm.expectRevert(IFeeTapper.InvalidReleaseRate.selector);
    feeTapper.setReleaseRate(_perBlockReleaseRate);
  }

  function test_setReleaseRate_WhenLTEBPSAndDivisibleByBPS(uint24 _perBlockReleaseRate) public {
    // it succeeds

    _perBlockReleaseRate = uint24(bound(_perBlockReleaseRate, 1, BPS));
    vm.assume(BPS % _perBlockReleaseRate == 0);

    vm.prank(owner);
    vm.expectEmit(true, true, true, true);
    emit IFeeTapper.ReleaseRateSet(_perBlockReleaseRate);
    feeTapper.setReleaseRate(_perBlockReleaseRate);
    assertEq(feeTapper.perBlockReleaseRate(), _perBlockReleaseRate);
  }

  /// forge-config: default.isolate = true
  /// forge-config: ci.isolate = true
  function test_sync_gas() public {
    Currency currency = Currency.wrap(address(erc20Currency));
    deal(address(erc20Currency), address(feeTapper), 1e18);
    feeTapper.sync(currency);
    vm.snapshotGasLastCall("sync_newTap");

    deal(address(erc20Currency), address(feeTapper), 1e18);
    feeTapper.sync(currency);
    vm.snapshotGasLastCall("sync_existingTap");
  }

  function test_sync_WhenAmountIsTooLarge() public {
    // it reverts with {AmountTooLarge()}

    Currency currency = Currency.wrap(address(erc20Currency));
    deal(address(erc20Currency), address(feeTapper), feeTapper.MAX_BALANCE() + 1);
    vm.expectRevert(IFeeTapper.AmountTooLarge.selector);
    feeTapper.sync(currency);
  }

  function test_sync_WhenCurrencyIsNotAddressZero(uint192 _feeAmount) public {
    // it emits a {Synced()} event

    _feeAmount = uint192(bound(_feeAmount, 1, feeTapper.MAX_BALANCE()));

    Currency currency = Currency.wrap(address(erc20Currency));

    deal(address(erc20Currency), address(feeTapper), _feeAmount);

    vm.expectEmit(true, true, true, true);
    emit IFeeTapper.Synced(Currency.unwrap(currency), _feeAmount);
    feeTapper.sync(currency);
    assertEq(feeTapper.taps(currency).balance, _feeAmount);
  }

  function test_sync_WhenCurrencyIsAddressZeroAndTapIsNotEmpty(
    uint192 _feeAmount,
    uint192 _additionalFeeAmount,
    uint64 _elapsed,
    bool _useNativeCurrency
  ) public {
    // it adds fee amount to the tap balance
    // it creates a new keg
    // it emits a {Deposited()} event
    // it emits a {Synced()} event

    // Low bounds to avoid overflows later on
    _feeAmount = uint192(bound(_feeAmount, 1, type(uint64).max));
    _additionalFeeAmount = uint192(bound(_additionalFeeAmount, 1, type(uint64).max));

    Currency currency =
      _useNativeCurrency ? Currency.wrap(address(0)) : Currency.wrap(address(erc20Currency));
    _deal(address(feeTapper), _feeAmount, _useNativeCurrency);
    feeTapper.sync(currency);
    assertEq(feeTapper.taps(currency).balance, _feeAmount);

    _deal(address(feeTapper), _additionalFeeAmount, _useNativeCurrency);
    feeTapper.sync(currency);
    assertEq(feeTapper.taps(currency).balance, _feeAmount + _additionalFeeAmount);

    _elapsed = uint64(bound(_elapsed, 1, BPS / feeTapper.perBlockReleaseRate()));

    vm.roll(block.number + _elapsed);
    uint256 released = feeTapper.releaseAll(currency);
    assertEq(
      released,
      (_feeAmount + _additionalFeeAmount) * feeTapper.perBlockReleaseRate() * _elapsed / BPS
    );
  }

  function test_release_WhenTapAmountIsZero(Currency currency) public {
    // it returns 0

    uint256 amount = feeTapper.releaseAll(currency);
    assertEq(amount, 0);
  }

  function test_release_WhenElapsedIsZero(uint192 _feeAmount) public {
    // it returns 0

    _feeAmount = uint192(bound(_feeAmount, 1, feeTapper.MAX_BALANCE()));

    Currency currency = Currency.wrap(address(0));
    _deal(address(feeTapper), _feeAmount, true);
    feeTapper.sync(currency);

    assertEq(feeTapper.taps(currency).balance, _feeAmount);

    uint256 amount = feeTapper.releaseAll(currency);
    assertEq(amount, 0);
  }

  /// forge-config: default.isolate = true
  /// forge-config: ci.isolate = true
  function test_release_nativeCurrency_single_gas() public {
    Currency currency = Currency.wrap(address(0));
    _deal(address(feeTapper), 1e18, true);
    feeTapper.sync(currency);

    vm.roll(block.number + 1);
    feeTapper.releaseAll(currency);
    vm.snapshotGasLastCall("release_nativeCurrency_single");

    vm.roll(block.number + BPS);
    feeTapper.releaseAll(currency);
    vm.snapshotGasLastCall("release_nativeCurrency_single_deletion");
  }

  /// forge-config: default.isolate = true
  /// forge-config: ci.isolate = true
  function test_release_keg_nativeCurrency_gas() public {
    Currency currency = Currency.wrap(address(0));
    _deal(address(feeTapper), 1e18, true);
    feeTapper.sync(currency);

    vm.roll(block.number + 1);
    feeTapper.release(1);
    vm.snapshotGasLastCall("release_keg_nativeCurrency_single");

    vm.roll(block.number + BPS);
    feeTapper.release(1);
    vm.snapshotGasLastCall("release_keg_nativeCurrency_single_deletion");
  }

  /// forge-config: default.isolate = true
  /// forge-config: ci.isolate = true
  function test_release_erc20Currency_single_gas() public {
    Currency currency = Currency.wrap(address(erc20Currency));
    _deal(address(feeTapper), 1e18, false);
    feeTapper.sync(currency);

    vm.roll(block.number + 1);
    feeTapper.releaseAll(currency);
    vm.snapshotGasLastCall("release_erc20Currency_single");

    vm.roll(block.number + BPS);
    feeTapper.releaseAll(currency);
    vm.snapshotGasLastCall("release_erc20Currency_single_deletion");
  }

  /// forge-config: default.isolate = true
  /// forge-config: ci.isolate = true
  function test_release_keg_erc20Currency_gas() public {
    Currency currency = Currency.wrap(address(erc20Currency));
    _deal(address(feeTapper), 1e18, false);
    feeTapper.sync(currency);

    vm.roll(block.number + 1);
    feeTapper.release(1);
    vm.snapshotGasLastCall("release_keg_erc20Currency_single");

    vm.roll(block.number + BPS);
    feeTapper.release(1);
    vm.snapshotGasLastCall("release_keg_erc20Currency_single_deletion");
  }

  /// forge-config: default.isolate = true
  /// forge-config: ci.isolate = true
  function test_release_nativeCurrency_multiple_gas() public {
    Currency currency = Currency.wrap(address(0));
    for (uint64 i = 0; i < 3; i++) {
      _deal(address(feeTapper), 1e18, true);
      feeTapper.sync(currency);
    }

    vm.roll(block.number + 1);
    feeTapper.releaseAll(currency);
    vm.snapshotGasLastCall("release_nativeCurrency_multiple");

    vm.roll(block.number + BPS);
    feeTapper.releaseAll(currency);
    vm.snapshotGasLastCall("release_nativeCurrency_multiple_deletion");
  }

  function test_release_WhenToReleaseIsGreaterThanTapAmount(uint192 _feeAmount, uint64 _elapsed)
    public
  {
    // it returns the rest of the tap amount

    _elapsed = uint64(bound(_elapsed, BPS / feeTapper.perBlockReleaseRate(), type(uint64).max));
    _feeAmount = uint192(bound(_feeAmount, 1, feeTapper.MAX_BALANCE()));

    Currency currency = Currency.wrap(address(0));
    _deal(address(feeTapper), _feeAmount, true);
    feeTapper.sync(currency);

    // ensure that there is more to release than the tap amount
    vm.roll(block.number + _elapsed);

    uint256 amount = feeTapper.releaseAll(currency);
    assertEq(amount, _feeAmount);
    assertEq(feeTapper.taps(currency).balance, 0);
  }

  function test_release_WhenToReleaseIsLTEThanTapAmount(
    uint192 _feeAmount,
    uint64 _elapsed,
    bool _useNativeCurrency
  ) public {
    // it updates the tap amount
    // it emits a {Released()} event

    _elapsed = uint64(bound(_elapsed, 1, BPS / feeTapper.perBlockReleaseRate()));
    _feeAmount = uint192(bound(_feeAmount, 1, feeTapper.MAX_BALANCE()));

    Currency currency =
      _useNativeCurrency ? Currency.wrap(address(0)) : Currency.wrap(address(erc20Currency));
    _deal(address(feeTapper), _feeAmount, _useNativeCurrency);
    feeTapper.sync(currency);

    assertEq(feeTapper.taps(currency).balance, _feeAmount);

    vm.roll(block.number + _elapsed);
    vm.expectEmit(true, true, true, true);
    uint192 expectedReleased = (_feeAmount * feeTapper.perBlockReleaseRate() * _elapsed) / BPS;
    emit IFeeTapper.Released(Currency.unwrap(currency), expectedReleased);
    vm.assume(expectedReleased > 0);
    uint192 released = feeTapper.releaseAll(currency);
    assertEq(released, expectedReleased);
    assertEq(feeTapper.taps(currency).balance, _feeAmount - released);
  }

  function test_release_IsLinear(uint192 _feeAmount, bool _useNativeCurrency) public {
    // it releases the amount of protocol fees based on the release rate

    _feeAmount = uint192(bound(_feeAmount, 1, feeTapper.MAX_BALANCE()));

    Currency currency =
      _useNativeCurrency ? Currency.wrap(address(0)) : Currency.wrap(address(erc20Currency));
    _deal(address(feeTapper), _feeAmount, _useNativeCurrency);
    feeTapper.sync(currency);

    uint256 snapshotId = vm.snapshot();

    // Maximize number of releases by calling one per block
    uint192 totalReleased = 0;
    uint256 maxDust = 0;
    for (uint64 i = 0; i < BPS / feeTapper.perBlockReleaseRate(); i++) {
      vm.roll(block.number + 1);
      totalReleased += feeTapper.releaseAll(currency);
      maxDust++;
    }

    vm.revertTo(snapshotId);

    // Now test releasing all in one go after BPS / perBlockReleaseRate() blocks
    vm.roll(block.number + BPS / feeTapper.perBlockReleaseRate());
    uint256 endTotalReleased = feeTapper.releaseAll(currency);
    assertApproxEqAbs(endTotalReleased, totalReleased, maxDust, "total released should be the same");
  }

  function test_release_WhenEmptyKegsAreReleased(
    uint192 _feeAmount,
    uint192 _additionalFeeAmount,
    bool _useNativeCurrency
  ) public {
    // it does not delete the keg when fully released
    // it does not update the head/tail of the tap
    // after adding a new keg, the old keg is deleted
    // after releasing the new keg, it becomes the head/tail of the tap

    _feeAmount = uint192(bound(_feeAmount, 1, feeTapper.MAX_BALANCE()));
    _additionalFeeAmount = uint192(bound(_additionalFeeAmount, 1, feeTapper.MAX_BALANCE()));

    Currency currency =
      _useNativeCurrency ? Currency.wrap(address(0)) : Currency.wrap(address(erc20Currency));
    _deal(address(feeTapper), _feeAmount, _useNativeCurrency);
    feeTapper.sync(currency);

    uint48 endBlock = uint48(block.number + BPS / feeTapper.perBlockReleaseRate());

    vm.roll(block.number + BPS / feeTapper.perBlockReleaseRate());
    uint192 released = feeTapper.release(1);
    assertEq(released, _feeAmount);
    assertEq(feeTapper.taps(currency).balance, 0);

    // assert that the keg is not deleted
    assertEq(feeTapper.taps(currency).head, 1);
    assertEq(feeTapper.taps(currency).tail, 1);
    assertEq(feeTapper.kegs(1).perBlockReleaseAmount, _feeAmount * feeTapper.perBlockReleaseRate());
    assertEq(feeTapper.kegs(1).endBlock, endBlock);

    // make another deposit
    _deal(address(feeTapper), _additionalFeeAmount, _useNativeCurrency);
    feeTapper.sync(currency);

    vm.roll(block.number + 1);
    released = feeTapper.releaseAll(currency);

    // assert that the old keg is deleted and the new keg is the head/tail
    assertEq(feeTapper.taps(currency).head, 2);
    assertEq(feeTapper.taps(currency).tail, 2);
    assertEq(feeTapper.kegs(1).perBlockReleaseAmount, 0);
    assertEq(feeTapper.kegs(1).endBlock, 0);

    // assert that after the full release, the head/tail are reset
    vm.roll(block.number + BPS / feeTapper.perBlockReleaseRate());
    released = feeTapper.releaseAll(currency);
    assertEq(feeTapper.taps(currency).head, 0);
    assertEq(feeTapper.taps(currency).tail, 0);
  }

  function test_release_WhenMiddleKegIsReleased(uint192 _feeAmount, bool _useNativeCurrency)
    public
  {
    // it deletes the keg when fully released
    // it keeps the current head/tail of the tap
    // it links the head to the next keg

    _feeAmount = uint192(bound(_feeAmount, 1, feeTapper.MAX_BALANCE() / 3));

    Currency currency =
      _useNativeCurrency ? Currency.wrap(address(0)) : Currency.wrap(address(erc20Currency));
    _deal(address(feeTapper), _feeAmount, _useNativeCurrency);
    feeTapper.sync(currency);

    uint24 originalReleaseRate = feeTapper.perBlockReleaseRate();
    // Modify the release rate to have the second keg run out before the first and third. It will
    // run out in a block
    vm.prank(owner);
    feeTapper.setReleaseRate(BPS);

    // add a second keg
    _deal(address(feeTapper), _feeAmount, _useNativeCurrency);
    feeTapper.sync(currency);

    // Change the release rate back to the original
    vm.prank(owner);
    feeTapper.setReleaseRate(originalReleaseRate);

    // add a third keg
    _deal(address(feeTapper), _feeAmount, _useNativeCurrency);
    feeTapper.sync(currency);

    // release the middle keg
    vm.roll(block.number + 1);
    uint192 released = feeTapper.releaseAll(currency);
    assertEq(released, _feeAmount + (_feeAmount * originalReleaseRate * 2) / BPS);
    // Same head and tail
    assertEq(feeTapper.taps(currency).head, 1);
    assertEq(feeTapper.taps(currency).tail, 3);
    assertEq(feeTapper.kegs(1).next, 3);
    assertEq(feeTapper.kegs(3).next, 0);
  }

  function test_release_WhenMultipleKegsAreReleased(uint192 _feeAmount, bool _useNativeCurrency)
    public
  {
    // it moves the head over multiple

    _feeAmount = uint192(bound(_feeAmount, 1, feeTapper.MAX_BALANCE() / 3));

    Currency currency =
      _useNativeCurrency ? Currency.wrap(address(0)) : Currency.wrap(address(erc20Currency));
    _deal(address(feeTapper), _feeAmount, _useNativeCurrency);
    feeTapper.sync(currency);

    // add a second keg
    _deal(address(feeTapper), _feeAmount, _useNativeCurrency);
    feeTapper.sync(currency);

    uint48 endBlock = uint48(block.number + BPS / feeTapper.perBlockReleaseRate());

    vm.roll(block.number + 1);
    // add a third keg
    _deal(address(feeTapper), _feeAmount, _useNativeCurrency);
    feeTapper.sync(currency);

    // roll to the end of the first two releases
    vm.roll(endBlock);
    feeTapper.releaseAll(currency);
    // head should have been moved from 1 -> 2 -> 3
    assertEq(feeTapper.taps(currency).head, 3);
    assertEq(feeTapper.taps(currency).tail, 3);
    assertEq(feeTapper.kegs(1).perBlockReleaseAmount, 0); // deleted
    assertEq(feeTapper.kegs(1).next, 0); // deleted
    assertEq(feeTapper.kegs(2).perBlockReleaseAmount, 0); // deleted
    assertEq(feeTapper.kegs(2).next, 0); // deleted
    assertEq(feeTapper.kegs(3).next, 0); // last one
  }

  function test_release_WhenTailKegEndsBeforeHead_ReLinksCorrectly(
    uint192 _feeAmount,
    bool _useNativeCurrency
  ) public {
    // it deletes the finished tail keg and keeps the list linked for new deposits

    _feeAmount = uint192(bound(_feeAmount, 1, feeTapper.MAX_BALANCE() / 3));

    Currency currency =
      _useNativeCurrency ? Currency.wrap(address(0)) : Currency.wrap(address(erc20Currency));

    // first keg with the default, slower release rate
    _deal(address(feeTapper), _feeAmount, _useNativeCurrency);
    feeTapper.sync(currency);

    uint24 originalReleaseRate = feeTapper.perBlockReleaseRate();

    // speed up release so the next keg finishes first
    vm.prank(owner);
    feeTapper.setReleaseRate(BPS);

    // second keg (will end in 1 block)
    _deal(address(feeTapper), _feeAmount, _useNativeCurrency);
    feeTapper.sync(currency);

    // advance so the tail keg ends while the head is still active
    vm.roll(block.number + 1);
    uint192 released = feeTapper.releaseAll(currency);
    assertGt(released, 0);

    // tail was removed; head remains
    assertEq(feeTapper.taps(currency).head, 1);
    assertEq(feeTapper.taps(currency).tail, 1);
    assertEq(feeTapper.kegs(1).next, 0);

    // restore original rate and add a new keg; it should link after the head
    vm.prank(owner);
    feeTapper.setReleaseRate(originalReleaseRate);

    _deal(address(feeTapper), _feeAmount, _useNativeCurrency);
    feeTapper.sync(currency);

    assertEq(feeTapper.taps(currency).head, 1);
    assertEq(feeTapper.taps(currency).tail, 3);
    assertEq(feeTapper.kegs(1).next, 3);
    assertEq(feeTapper.kegs(3).next, 0);
  }

  function test_release_WhenConsecutiveFinishedKegsBehindActiveHead_ReLinksCorrectly(
    uint192 _feeAmount,
    bool _useNativeCurrency
  ) public {
    // it deletes consecutive finished middle kegs and keeps the tail reachable

    _feeAmount = uint192(bound(_feeAmount, 1, feeTapper.MAX_BALANCE() / 4));

    Currency currency =
      _useNativeCurrency ? Currency.wrap(address(0)) : Currency.wrap(address(erc20Currency));

    // Keg A (head) with slow release
    _deal(address(feeTapper), _feeAmount, _useNativeCurrency);
    feeTapper.sync(currency);

    uint24 originalReleaseRate = feeTapper.perBlockReleaseRate();

    // Speed up to make middle kegs finish quickly
    vm.prank(owner);
    feeTapper.setReleaseRate(BPS);

    // Keg B
    _deal(address(feeTapper), _feeAmount, _useNativeCurrency);
    feeTapper.sync(currency);

    // Keg C
    _deal(address(feeTapper), _feeAmount, _useNativeCurrency);
    feeTapper.sync(currency);

    // Restore slower rate for tail keg D
    vm.prank(owner);
    feeTapper.setReleaseRate(originalReleaseRate);

    // Keg D (tail, long-lived)
    _deal(address(feeTapper), _feeAmount, _useNativeCurrency);
    feeTapper.sync(currency);

    // Roll so B and C have fully ended while A and D are still active
    vm.roll(block.number + 1);

    uint192 released = feeTapper.releaseAll(currency);
    assertGt(released, 0);

    // A should link directly to D; tail is D; B and C are deleted
    assertEq(feeTapper.taps(currency).head, 1);
    assertEq(feeTapper.taps(currency).tail, 4);
    assertEq(feeTapper.kegs(1).next, 4);
    assertEq(feeTapper.kegs(4).next, 0);
    assertEq(feeTapper.kegs(2).perBlockReleaseAmount, 0);
    assertEq(feeTapper.kegs(3).perBlockReleaseAmount, 0);
  }
}
