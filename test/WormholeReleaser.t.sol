// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";

import {WormholeReleaser} from "../src/releasers/WormholeReleaser.sol";
import {IReleaser} from "../src/interfaces/IReleaser.sol";

import {MockEmptyERC20} from "./mocks/MockEmptyERC20.sol";
import {MockTokenJar, Currency} from "./mocks/MockTokenJar.sol";
import {MockNttManager} from "./mocks/MockNttManager.sol";
import {MockWormhole} from "./mocks/MockWormhole.sol";
import {MockReleaserCaller} from "./mocks/MockReleaserCaller.sol";

contract WormholeReleaserTest is Test {
    WormholeReleaser releaser;
    MockNttManager nttManager;
    MockTokenJar tokenJar;
    MockWormhole wormhole;
    MockEmptyERC20 uni;
    MockReleaserCaller releaserCaller;

    uint256 defaultThreshold = 1 ether;

    address admin = vm.addr(1);
    address bob = vm.addr(2);
    address charlie = vm.addr(2);

    function setUp() public {
        nttManager = new MockNttManager();
        wormhole = new MockWormhole();
        tokenJar = new MockTokenJar();
        uni = new MockEmptyERC20();
        releaserCaller = new MockReleaserCaller();

        vm.prank(admin);
        releaser = new WormholeReleaser({
            _wormhole: address(wormhole),
            _nttManager: address(nttManager),
            _resource: address(uni),
            _threshold: defaultThreshold,
            _tokenJar: address(tokenJar)
        });

        vm.prank(admin);
        releaser.setThresholdSetter(admin);
    }

    function testRelease() external {
        uint256 nonce = releaser.nonce();
        Currency[] memory assets = new Currency[](0);

        vm.expectEmit(true, true, true, true, address(uni));
        emit MockEmptyERC20.MockTransfer(bob, address(releaser), defaultThreshold);

        vm.expectEmit(true, true, true, true, address(tokenJar));
        emit MockTokenJar.MockRelease(address(releaser), bob, assets);

        vm.expectEmit(true, true, true, true, address(releaser));
        emit IReleaser.Released(nonce, bob, assets);

        vm.expectEmit(true, true, true, true, address(uni));
        emit MockEmptyERC20.MockApproval(address(releaser), address(nttManager), defaultThreshold);

        vm.expectEmit(true, true, true, true, address(nttManager));
        emit MockNttManager.MockTransfer(
            defaultThreshold,
            releaser.WORMHOLE_DEFINED_ETH_CHAIN_ID(),
            releaser.BURN_ADDRESS(),
            address(releaser),
            0
        );

        vm.prank(bob);
        releaser.release({_nonce: nonce, assets: assets, recipient: bob});
    }

    function testReleaseMultipleAssets() external {
        uint256 nonce = releaser.nonce();
        Currency[] memory assets = new Currency[](2);
        assets[0] = Currency.wrap(address(0x01));
        assets[1] = Currency.wrap(address(0x02));

        vm.expectEmit(true, true, true, true, address(uni));
        emit MockEmptyERC20.MockTransfer(bob, address(releaser), defaultThreshold);

        vm.expectEmit(true, true, true, true, address(tokenJar));
        emit MockTokenJar.MockRelease(address(releaser), bob, assets);

        vm.expectEmit(true, true, true, true, address(releaser));
        emit IReleaser.Released(nonce, bob, assets);

        vm.expectEmit(true, true, true, true, address(uni));
        emit MockEmptyERC20.MockApproval(address(releaser), address(nttManager), defaultThreshold);

        vm.expectEmit(true, true, true, true, address(nttManager));
        emit MockNttManager.MockTransfer(
            defaultThreshold,
            releaser.WORMHOLE_DEFINED_ETH_CHAIN_ID(),
            releaser.BURN_ADDRESS(),
            address(releaser),
            0
        );

        vm.prank(bob);
        releaser.release({_nonce: nonce, assets: assets, recipient: bob});
    }

    function testReleaseWithWormholeFee() external {
        uint256 wormholeFee = 2 ether;
        uint256 nonce = releaser.nonce();
        Currency[] memory assets = new Currency[](2);
        assets[0] = Currency.wrap(address(0x01));
        assets[1] = Currency.wrap(address(0x02));

        wormhole.mockSetMessageFee(wormholeFee);

        vm.deal(address(releaserCaller), wormholeFee);

        vm.expectEmit(true, true, true, true, address(uni));
        emit MockEmptyERC20.MockTransfer(address(releaserCaller), address(releaser), defaultThreshold);

        vm.expectEmit(true, true, true, true, address(tokenJar));
        emit MockTokenJar.MockRelease(address(releaser), bob, assets);

        vm.expectEmit(true, true, true, true, address(releaser));
        emit IReleaser.Released(nonce, bob, assets);

        vm.expectEmit(true, true, true, true, address(uni));
        emit MockEmptyERC20.MockApproval(address(releaser), address(nttManager), defaultThreshold);

        vm.expectEmit(true, true, true, true, address(nttManager));
        emit MockNttManager.MockTransfer(
            defaultThreshold,
            releaser.WORMHOLE_DEFINED_ETH_CHAIN_ID(),
            releaser.BURN_ADDRESS(),
            address(releaser),
            wormholeFee
        );

        releaserCaller.doReleaserCall(releaser, wormholeFee, nonce, assets, bob);

        assertEq(address(releaserCaller).balance, 0);
        assertEq(address(nttManager).balance, wormholeFee);
    }

    function testReleaseWithWormholeFeeRefund() external {
        uint256 wormholeFee = 2 ether;
        uint256 nonce = releaser.nonce();
        Currency[] memory assets = new Currency[](2);
        assets[0] = Currency.wrap(address(0x01));
        assets[1] = Currency.wrap(address(0x02));

        wormhole.mockSetMessageFee(wormholeFee);

        vm.deal(address(releaserCaller), wormholeFee + 1);

        vm.expectEmit(true, true, true, true, address(uni));
        emit MockEmptyERC20.MockTransfer(address(releaserCaller), address(releaser), defaultThreshold);

        vm.expectEmit(true, true, true, true, address(tokenJar));
        emit MockTokenJar.MockRelease(address(releaser), bob, assets);

        vm.expectEmit(true, true, true, true, address(releaser));
        emit IReleaser.Released(nonce, bob, assets);

        vm.expectEmit(true, true, true, true, address(uni));
        emit MockEmptyERC20.MockApproval(address(releaser), address(nttManager), defaultThreshold);

        vm.expectEmit(true, true, true, true, address(nttManager));
        emit MockNttManager.MockTransfer(
            defaultThreshold,
            releaser.WORMHOLE_DEFINED_ETH_CHAIN_ID(),
            releaser.BURN_ADDRESS(),
            address(releaser),
            wormholeFee
        );

        vm.expectEmit(true, true, true, true, address(releaserCaller));
        emit MockReleaserCaller.MockReceive(address(releaser), 1);

        releaserCaller.doReleaserCall(releaser, wormholeFee + 1, nonce, assets, bob);

        assertEq(address(releaserCaller).balance, 1);
        assertEq(address(nttManager).balance, wormholeFee);
    }

    function testReleaseWithWormholeFeeRefundFails() external {
        uint256 wormholeFee = 2 ether;
        uint256 nonce = releaser.nonce();
        Currency[] memory assets = new Currency[](2);
        assets[0] = Currency.wrap(address(0x01));
        assets[1] = Currency.wrap(address(0x02));

        wormhole.mockSetMessageFee(wormholeFee);
        releaserCaller.mockSetShouldThrow(true);

        vm.deal(address(releaserCaller), wormholeFee + 1);

        vm.expectRevert();
        releaserCaller.doReleaserCall(releaser, wormholeFee + 1, nonce, assets, bob);

        assertEq(address(releaserCaller).balance, wormholeFee + 1);
        assertEq(address(nttManager).balance, 0);
    }

    struct ShouldThrow {
        bool releaserCaller;
        bool tokenJar;
        bool uni;
        bool nttManager;
    }

    function testFuzzRelease(
        uint256 threshold,
        uint256 wormholeFee,
        uint256 amountPaid,
        Currency[] calldata assets,
        address recipient,
        ShouldThrow calldata shouldThrow
    ) external {
        uint256 nonce = releaser.nonce();

        wormhole.mockSetMessageFee(wormholeFee);
        releaserCaller.mockSetShouldThrow(shouldThrow.releaserCaller);
        tokenJar.mockSetShouldThrow(shouldThrow.tokenJar);
        uni.mockSetShouldThrow(shouldThrow.uni);
        nttManager.mockSetShouldThrow(shouldThrow.nttManager);

        vm.prank(admin);
        releaser.setThreshold(threshold);

        vm.deal(address(releaserCaller), amountPaid);

        bool shouldSucceed = true;

        // if amount paid is insufficient, it will throw
        shouldSucceed = shouldSucceed && amountPaid >= wormholeFee;

        // if amount paid is greater than the fee, then if releaser caller throws, it will throw
        //
        // aka: amount paid must match the fee OR releaser caller cannot throw
        shouldSucceed = shouldSucceed && (amountPaid == wormholeFee || !shouldThrow.releaserCaller);

        // if any of these throw, it will throw
        shouldSucceed = shouldSucceed && !shouldThrow.tokenJar;
        shouldSucceed = shouldSucceed && !shouldThrow.uni;
        shouldSucceed = shouldSucceed && !shouldThrow.nttManager;

        // if assets length is too high, it will throw
        shouldSucceed = shouldSucceed && assets.length <= 20;

        if (shouldSucceed) {
            vm.expectEmit(true, true, true, true, address(uni));
            emit MockEmptyERC20.MockTransfer(address(releaserCaller), address(releaser), threshold);

            vm.expectEmit(true, true, true, true, address(tokenJar));
            emit MockTokenJar.MockRelease(address(releaser), recipient, assets);

            vm.expectEmit(true, true, true, true, address(releaser));
            emit IReleaser.Released(nonce, recipient, assets);

            vm.expectEmit(true, true, true, true, address(uni));
            emit MockEmptyERC20.MockApproval(address(releaser), address(nttManager), threshold);

            vm.expectEmit(true, true, true, true, address(nttManager));
            emit MockNttManager.MockTransfer(
                threshold,
                releaser.WORMHOLE_DEFINED_ETH_CHAIN_ID(),
                releaser.BURN_ADDRESS(),
                address(releaser),
                wormholeFee
            );

            if (amountPaid > wormholeFee) {
                vm.expectEmit(true, true, true, true, address(releaserCaller));
                emit MockReleaserCaller.MockReceive(address(releaser), amountPaid - wormholeFee);
            }
        } else {
            vm.expectRevert();
        }

        releaserCaller.doReleaserCall(
            releaser,
            amountPaid,
            nonce,
            assets,
            recipient
        );

        if (shouldSucceed) {
            assertEq(address(releaserCaller).balance, amountPaid - wormholeFee);
            assertEq(address(releaser).balance, 0);
            assertEq(address(nttManager).balance, wormholeFee);
        } else {
            assertEq(address(releaserCaller).balance, amountPaid);
            assertEq(address(releaser).balance, 0);
            assertEq(address(nttManager).balance, 0);
        }
    }
}
