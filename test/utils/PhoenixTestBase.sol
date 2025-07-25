// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {RevertingToken} from "../mocks/RevertingToken.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Firepit} from "../../src/Firepit.sol";
import {AssetSink} from "../../src/AssetSink.sol";
import {OPStackFirepitSource} from "../../src/crosschain/OPStackFirepitSource.sol";
import {FirepitDestination} from "../../src/crosschain/FirepitDestination.sol";

import {MockCrossDomainMessenger} from "../mocks/MockCrossDomainMessenger.sol";

contract PhoenixTestBase is Test {
  address owner;
  address alice;
  address bob;
  MockERC20 resource;
  MockERC20 mockToken;
  RevertingToken revertingToken;

  AssetSink assetSink;
  Firepit firepit;
  OPStackFirepitSource opStackFirepitSource;
  MockCrossDomainMessenger mockCrossDomainMessenger = new MockCrossDomainMessenger();
  FirepitDestination firepitDestination;

  uint256 public constant INITIAL_TOKEN_AMOUNT = 1000e18;
  uint256 public constant INITIAL_NATIVE_AMOUNT = 10 ether;

  Currency[] releaseMockToken = new Currency[](1);
  Currency[] releaseMockNative = new Currency[](1);
  Currency[] releaseMockReverting = new Currency[](1);
  Currency[] releaseMockTokens = new Currency[](2);
  Currency[] releaseMockBoth = new Currency[](2);
  Currency[][] fuzzReleaseAny = new Currency[][](2);

  function setUp() public virtual {
    owner = makeAddr("owner");
    alice = makeAddr("alice");
    bob = makeAddr("bob");

    resource = new MockERC20("BurnableResource", "BNR", 18);
    mockToken = new MockERC20("MockToken", "MTK", 18);
    revertingToken = new RevertingToken("RevertingToken", "RTK", 18);
    assetSink = new AssetSink(owner);
    firepit = new Firepit(address(resource), INITIAL_TOKEN_AMOUNT, address(assetSink));

    firepitDestination = new FirepitDestination(owner, address(assetSink));
    opStackFirepitSource = new OPStackFirepitSource(
      address(resource),
      INITIAL_TOKEN_AMOUNT,
      address(mockCrossDomainMessenger),
      address(firepitDestination)
    );

    revertingToken.setRevertFrom(address(assetSink), true);

    vm.startPrank(owner);
    firepitDestination.setAllowableSource(address(opStackFirepitSource), true);
    firepitDestination.setAllowableCallers(address(mockCrossDomainMessenger), true);
    vm.stopPrank();

    // Supply tokens to the AssetSink
    mockToken.mint(address(assetSink), INITIAL_TOKEN_AMOUNT);
    revertingToken.mint(address(assetSink), INITIAL_TOKEN_AMOUNT);

    // Supply native tokens to the AssetSink
    vm.deal(address(assetSink), INITIAL_NATIVE_AMOUNT);

    // Define releasable assets
    __createReleaseArrays();

    // Mint burnable resource to test users
    resource.mint(alice, INITIAL_TOKEN_AMOUNT);
    resource.mint(bob, INITIAL_TOKEN_AMOUNT);

    vm.deal(alice, INITIAL_NATIVE_AMOUNT);
    vm.deal(bob, INITIAL_NATIVE_AMOUNT);
  }

  function __createReleaseArrays() private {
    releaseMockToken[0] = Currency.wrap(address(mockToken));
    releaseMockNative[0] = CurrencyLibrary.ADDRESS_ZERO;
    releaseMockReverting[0] = Currency.wrap(address(revertingToken));

    releaseMockBoth[0] = Currency.wrap(address(mockToken));
    releaseMockBoth[1] = CurrencyLibrary.ADDRESS_ZERO;

    releaseMockTokens[0] = Currency.wrap(address(mockToken));
    releaseMockTokens[1] = Currency.wrap(address(revertingToken));

    fuzzReleaseAny[0] = releaseMockToken;
    fuzzReleaseAny[1] = releaseMockNative;
  }
}
