// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Currency} from "v4-core/types/Currency.sol";

import {Firepit} from "../src/Firepit.sol";
import {AssetSink} from "../src/AssetSink.sol";

contract FirepitTest is Test {
  AssetSink assetSink;
  address owner;
  address alice;
  MockERC20 resource;
  MockERC20 mockToken;

  Firepit public firepit;

  uint256 public constant INITIAL_TOKEN_AMOUNT = 1000e18;

  function setUp() public {
    resource = new MockERC20("BurnableResource", "BNR", 18);
    mockToken = new MockERC20("MockToken", "MTK", 18);
    owner = makeAddr("owner");
    alice = makeAddr("alice");
    assetSink = new AssetSink(owner);

    firepit = new Firepit(address(resource), INITIAL_TOKEN_AMOUNT, address(assetSink));

    vm.prank(owner);
    assetSink.setReleaser(address(firepit));

    // Mint tokens and send to AssetSink
    mockToken.mint(address(assetSink), INITIAL_TOKEN_AMOUNT);

    // Mint burnable resource to a user.
    resource.mint(alice, INITIAL_TOKEN_AMOUNT);
  }

  function test_torch_success() public {
    // Assets to collect.
    Currency[] memory assets = new Currency[](1);
    assets[0] = Currency.wrap(address(mockToken));

    assertEq(resource.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
    assertEq(resource.balanceOf(address(firepit)), 0);
    assertEq(resource.balanceOf(address(0)), 0);

    vm.startPrank(alice);
    resource.approve(address(firepit), INITIAL_TOKEN_AMOUNT);
    firepit.torch(assets, alice);

    assertEq(mockToken.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
    assertEq(mockToken.balanceOf(address(assetSink)), 0);
    assertEq(resource.balanceOf(alice), 0);
    assertEq(resource.balanceOf(address(firepit)), 0);
    assertEq(resource.balanceOf(address(0)), INITIAL_TOKEN_AMOUNT);
  }
}
