// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {RevertingToken} from "../mocks/RevertingToken.sol";
import {OOGToken} from "../mocks/OOGToken.sol";
import {RevertBombToken} from "../mocks/RevertBombToken.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Firepit} from "../../src/releasers/Firepit.sol";
import {TokenJar, ITokenJar} from "../../src/TokenJar.sol";
import {IReleaser} from "../../src/interfaces/IReleaser.sol";

contract ProtocolFeesTestBase is Test {
  address owner;
  address alice;
  address bob;
  MockERC20 resource;
  MockERC20 mockToken;
  MockERC20 mockToken1;
  RevertingToken revertingToken;
  OOGToken oogToken;
  RevertBombToken revertBombToken;

  ITokenJar tokenJar;
  IReleaser firepit;

  uint256 public constant INITIAL_TOKEN_AMOUNT = 1000e18;
  uint256 public constant INITIAL_NATIVE_AMOUNT = 10 ether;

  Currency[] releaseMockToken = new Currency[](1);
  Currency[] releaseMockNative = new Currency[](1);
  Currency[] releaseMockReverting = new Currency[](1);
  Currency[] releaseMockOOG = new Currency[](1);
  Currency[] releaseMockRevertBomb = new Currency[](1);
  Currency[] releaseMalicious = new Currency[](3);
  Currency[] releaseMockTokens = new Currency[](2);
  Currency[] releaseMockBoth = new Currency[](2);
  Currency[][] fuzzReleaseAny = new Currency[][](4);

  struct TestBalances {
    uint256 resource;
    uint256 mockToken;
    uint256 revertingToken;
    uint256 oogToken;
    uint256 revertBombToken;
    uint256 native;
  }

  function setUp() public virtual {
    owner = makeAddr("owner");
    alice = makeAddr("alice");
    bob = makeAddr("bob");

    resource = new MockERC20("BurnableResource", "BNR", 18);
    mockToken = new MockERC20("MockToken", "MTK", 18);
    mockToken1 = new MockERC20("MockToken1", "MTK1", 18);
    revertingToken = new RevertingToken("RevertingToken", "RTK", 18);
    oogToken = new OOGToken("OOGToken", "OOGT", 18);
    revertBombToken = new RevertBombToken("RevertBombToken", "RBT", 18);

    vm.startPrank(owner);
    tokenJar = new TokenJar();
    firepit = new Firepit(address(resource), INITIAL_TOKEN_AMOUNT, address(tokenJar));

    firepit.setThresholdSetter(owner);

    revertingToken.setRevertFrom(address(tokenJar), true);

    vm.stopPrank();

    // Supply tokens to the TokenJar
    mockToken.mint(address(tokenJar), INITIAL_TOKEN_AMOUNT);
    revertingToken.mint(address(tokenJar), INITIAL_TOKEN_AMOUNT);
    oogToken.mint(address(tokenJar), INITIAL_TOKEN_AMOUNT);
    revertBombToken.mint(address(tokenJar), INITIAL_TOKEN_AMOUNT);

    // Supply native tokens to the TokenJar
    vm.deal(address(tokenJar), INITIAL_NATIVE_AMOUNT);

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
    releaseMockOOG[0] = Currency.wrap(address(oogToken));
    releaseMockRevertBomb[0] = Currency.wrap(address(revertBombToken));

    releaseMockBoth[0] = Currency.wrap(address(mockToken));
    releaseMockBoth[1] = CurrencyLibrary.ADDRESS_ZERO;

    releaseMockTokens[0] = Currency.wrap(address(mockToken));
    releaseMockTokens[1] = Currency.wrap(address(revertingToken));

    releaseMalicious[0] = Currency.wrap(address(revertingToken));
    releaseMalicious[1] = Currency.wrap(address(oogToken));
    releaseMalicious[2] = Currency.wrap(address(revertBombToken));

    fuzzReleaseAny[0] = releaseMockToken;
    fuzzReleaseAny[1] = releaseMockNative;
    fuzzReleaseAny[2] = releaseMockBoth;
    fuzzReleaseAny[3] = releaseMalicious;
  }

  function _testBalances(address _owner) internal view returns (TestBalances memory) {
    return TestBalances({
      resource: resource.balanceOf(_owner),
      mockToken: mockToken.balanceOf(_owner),
      revertingToken: revertingToken.balanceOf(_owner),
      oogToken: oogToken.balanceOf(_owner),
      revertBombToken: revertBombToken.balanceOf(_owner),
      native: CurrencyLibrary.ADDRESS_ZERO.balanceOf(_owner)
    });
  }
}
