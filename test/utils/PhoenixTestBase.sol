// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Currency} from "v4-core/types/Currency.sol";

import {Firepit} from "../../src/Firepit.sol";
import {AssetSink} from "../../src/AssetSink.sol";

contract PhoenixTestBase is Test {
  address owner;
  address alice;
  address bob;
  MockERC20 resource;
  MockERC20 mockToken;

  AssetSink assetSink;
  Firepit firepit;

  uint256 public constant INITIAL_TOKEN_AMOUNT = 1000e18;
  uint256 public constant INITIAL_NATIVE_AMOUNT = 10 ether;

  function setUp() public virtual {
    owner = makeAddr("owner");
    alice = makeAddr("alice");
    bob = makeAddr("bob");
    resource = new MockERC20("BurnableResource", "BNR", 18);
    mockToken = new MockERC20("MockToken", "MTK", 18);
    assetSink = new AssetSink(owner);

    firepit = new Firepit(address(resource), INITIAL_TOKEN_AMOUNT, address(assetSink));

    // Supply tokens to the AssetSink
    mockToken.mint(address(assetSink), INITIAL_TOKEN_AMOUNT);

    // Supply native tokens to the AssetSink
    vm.deal(address(assetSink), INITIAL_NATIVE_AMOUNT);

    // Mint burnable resource to test users
    resource.mint(alice, INITIAL_TOKEN_AMOUNT);
    resource.mint(bob, INITIAL_TOKEN_AMOUNT);

    vm.deal(alice, INITIAL_NATIVE_AMOUNT);
    vm.deal(bob, INITIAL_NATIVE_AMOUNT);
  }
}
