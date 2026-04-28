// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;


import {Test} from "forge-std/Test.sol";

import {SyntheticNttUni, ERC20} from "../src/wormhole/SyntheticNttUni.sol";

contract SyntheticNttUniTest is Test {
    SyntheticNttUni uni;
    address admin = vm.addr(1);
    address justSomeAccount = vm.addr(2);
    address initialNtt = address(0x66);

    function setUp() public {
        vm.prank(admin);
        uni = new SyntheticNttUni();

        vm.prank(admin);
        uni.setNtt(initialNtt);
    }

    function testSetNtt() public {
        address newNtt = address(0x67);

        vm.expectEmit(true, true, true, true, address(uni));
        emit SyntheticNttUni.NttSet(newNtt);

        vm.prank(admin);
        uni.setNtt(newNtt);

        assertEq(uni.ntt(), newNtt);
    }

    function testSetNttNotAdmin() public {
        address newNtt = address(0x67);

        vm.expectRevert();

        vm.prank(justSomeAccount);
        uni.setNtt(newNtt);

        assertEq(uni.ntt(), initialNtt);
    }

    function testFuzzSetNtt(address caller, address newNtt, bool coinToss) public {
        // makes caller == admin 50% of the time to explore more of the authenticated space.
        if (coinToss) {
            caller = admin;
        }

        if (caller == admin) {
            vm.expectEmit(true, true, true, true, address(uni));
            emit SyntheticNttUni.NttSet(newNtt);
        } else {
            vm.expectRevert();
        }

        vm.prank(caller); 
        uni.setNtt(newNtt);

        if (caller == admin) {
            assertEq(uni.ntt(), newNtt);
        } else {
            assertEq(uni.ntt(), initialNtt);
        }
    }

    function testMint() public {
        address receiver = address(0x67);
        uint256 amount = 67;

        assertEq(uni.balanceOf(receiver), 0);

        vm.expectEmit(true, true, true, true, address(uni));
        emit ERC20.Transfer(address(0x00), receiver, amount);

        vm.prank(initialNtt);
        uni.mint(receiver, amount);

        assertEq(uni.balanceOf(receiver), amount);
    }

    function testMintNotNtt() public {
        address receiver = address(0x67);
        uint256 amount = 67;

        assertEq(uni.balanceOf(receiver), 0);

        vm.expectRevert();

        uni.mint(receiver, amount);

        assertEq(uni.balanceOf(receiver), 0);
    }

    function testFuzzMint(address caller, address receiver, uint256 amount, bool coinToss) public {
        // makes caller == initialNtt 50% of the time to explore more of the authenticated space.
        if (coinToss) {
            caller = initialNtt;
        }

        assertEq(uni.balanceOf(receiver), 0);

        if (caller == initialNtt) {
            vm.expectEmit(true, true, true, true, address(uni));
            emit ERC20.Transfer(address(0x00), receiver, amount);
        } else {
            vm.expectRevert();
        }

        vm.prank(caller);
        uni.mint(receiver, amount);

        if (caller == initialNtt) {
            assertEq(uni.balanceOf(receiver), amount);
        } else {
            assertEq(uni.balanceOf(receiver), 0);
        }
    }

    function testBurn() public {
        uint256 amount = 67;

        vm.prank(initialNtt);
        uni.mint(initialNtt, amount);
        assertEq(uni.balanceOf(initialNtt), amount);

        vm.expectEmit(true, true, true, true, address(uni));
        emit ERC20.Transfer(initialNtt, address(0x00), amount);

        vm.prank(initialNtt);
        uni.burn(amount);

        assertEq(uni.balanceOf(initialNtt), 0);
    }

    function testBurnNotNtt() public {
        uint256 amount = 67;

        vm.prank(initialNtt);
        uni.mint(justSomeAccount, amount);
        assertEq(uni.balanceOf(justSomeAccount), amount);

        vm.expectRevert();

        vm.prank(justSomeAccount);
        uni.burn(amount);

        assertEq(uni.balanceOf(initialNtt), 0);
    }

    function testFuzzBurn(address caller, uint256 amount, bool coinToss) public {
        // makes caller == initialNtt 50% of the time to explore more of the authenticated space.
        if (coinToss) {
            caller = initialNtt;
        }

        vm.prank(initialNtt);
        uni.mint(caller, amount);

        if (caller == initialNtt) {
            vm.expectEmit(true, true, true, true, address(uni));
            emit ERC20.Transfer(caller, address(0x00), amount);
        } else {
            vm.expectRevert();
        }

        vm.prank(caller);
        uni.burn(amount);

        if (caller == initialNtt) {
            assertEq(uni.balanceOf(caller), 0);
        } else {
            assertEq(uni.balanceOf(caller), amount);
        }
    }
}
