// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";

import {WormholeReleaser} from "../../src/releasers/WormholeReleaser.sol";
import {TokenJar} from "../../src/TokenJar.sol";
import {IReleaser} from "../../src/interfaces/IReleaser.sol";

import {MockWormhole} from "../mocks/MockWormhole.sol";
import {MockReleaserCaller, Currency} from "../mocks/MockReleaserCaller.sol";
import {MockSyntheticNttUni, ERC20} from "../mocks/MockSyntheticNttUni.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IManagerBase} from "lib/native-token-transfers/evm/src/interfaces/IManagerBase.sol";
import {
  NttManagerNoRateLimiting
} from "lib/native-token-transfers/evm/src/NttManager/NttManagerNoRateLimiting.sol";
import {
  WormholeTransceiver
} from "lib/native-token-transfers/evm/src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";

library WormholeID {
  uint16 internal constant ETHEREUM = 2;
  uint16 internal constant CELO = 14;
  uint16 internal constant BNB_CHAIN = 4;
  uint16 internal constant POLYGON = 5;
}

struct Deployment {
  MockSyntheticNttUni uni;
  NttManagerNoRateLimiting nttManager;
  WormholeTransceiver transceiver;
  TokenJar tokenJar;
  MockWormhole wormhole;
  WormholeReleaser releaser;
}

contract WormholeReleaserIntegrationTest is Test {
  Deployment internal eth;
  Deployment internal pol;

  MockReleaserCaller internal caller;
  uint256 internal defaultThreshold = 1 ether;
  MockERC20[] internal tokens;
  uint256[] internal defaultAmounts;

  address admin = vm.addr(1);
  address bob = vm.addr(2);

  function setUp() public {
    vm.startPrank(admin);
    _deploy({net: eth, mode: IManagerBase.Mode.LOCKING, wormholeChainId: WormholeID.ETHEREUM});
    _deploy({net: pol, mode: IManagerBase.Mode.BURNING, wormholeChainId: WormholeID.POLYGON});

    _config({src: pol, dst: eth, wormholePeerChainId: WormholeID.ETHEREUM});
    _config({src: eth, dst: pol, wormholePeerChainId: WormholeID.POLYGON});

    caller = new MockReleaserCaller();

    tokens.push(new MockERC20("Test A", "A", 18));
    defaultAmounts.push(10);

    tokens.push(new MockERC20("Test B", "B", 18));
    defaultAmounts.push(20);

    vm.stopPrank();
  }

  // -- test functions ---------------------------------------------------------------------------
  //
  function testRelease() external {
    uint256 threshold = pol.releaser.threshold();
    uint256 wormholeFee = pol.wormhole.messageFee();
    uint256 nonce = pol.releaser.nonce();

    pol.uni.mockMint(address(caller), threshold);

    caller.doApproval(address(pol.uni), address(pol.releaser), threshold);

    vm.expectEmit(true, true, true, true, address(pol.uni));
    emit ERC20.Transfer(address(pol.nttManager), address(0x00), threshold);

    caller.doReleaserCall({
      releaser: pol.releaser,
      value: wormholeFee,
      nonce: nonce,
      assets: new Currency[](0),
      receiver: bob
    });

    assertEq(pol.uni.balanceOf(bob), 0);
    assertEq(pol.uni.balanceOf(address(caller)), 0);
    assertEq(pol.uni.balanceOf(address(pol.releaser)), 0);
  }

  function testReleaseTwice() external {
    uint256 threshold = pol.releaser.threshold();
    uint256 wormholeFee = pol.wormhole.messageFee();
    uint256 nonce = pol.releaser.nonce();

    pol.uni.mockMint(address(caller), threshold * 2);

    caller.doApproval(address(pol.uni), address(pol.releaser), threshold * 2);

    vm.expectEmit(true, true, true, true, address(pol.uni));
    emit ERC20.Transfer(address(pol.nttManager), address(0x00), threshold);

    caller.doReleaserCall({
      releaser: pol.releaser,
      value: wormholeFee,
      nonce: nonce,
      assets: new Currency[](0),
      receiver: bob
    });

    vm.expectEmit(true, true, true, true, address(pol.uni));
    emit ERC20.Transfer(address(pol.nttManager), address(0x00), threshold);

    caller.doReleaserCall({
      releaser: pol.releaser,
      value: wormholeFee,
      nonce: nonce + 1,
      assets: new Currency[](0),
      receiver: bob
    });

    assertEq(pol.uni.balanceOf(bob), 0);
    assertEq(pol.uni.balanceOf(address(caller)), 0);
    assertEq(pol.uni.balanceOf(address(pol.releaser)), 0);
  }

  function testReleaseWithAssets() external {
    uint256 threshold = pol.releaser.threshold();
    uint256 wormholeFee = pol.wormhole.messageFee();
    uint256 nonce = pol.releaser.nonce();

    uint256 length;
    Currency[] memory assets = new Currency[](length);
    uint256[] memory amounts = defaultAmounts;

    for (uint256 i; i < length; i++) {
      tokens[i].mint(address(pol.tokenJar), amounts[i]);

      assets[i] = Currency.wrap(address(tokens[i]));
    }

    pol.uni.mockMint(address(caller), threshold);

    caller.doApproval(address(pol.uni), address(pol.releaser), threshold);

    vm.expectEmit(true, true, true, true, address(pol.uni));
    emit ERC20.Transfer(address(pol.nttManager), address(0x00), threshold);

    caller.doReleaserCall({
      releaser: pol.releaser,
      value: wormholeFee,
      nonce: nonce,
      assets: new Currency[](0),
      receiver: bob
    });

    assertEq(pol.uni.balanceOf(bob), 0);
    assertEq(pol.uni.balanceOf(address(caller)), 0);
    assertEq(pol.uni.balanceOf(address(pol.releaser)), 0);

    for (uint256 i; i < length; i++) {
      MockERC20 token = tokens[i];

      assertEq(token.balanceOf(bob), amounts[i]);
      assertEq(token.balanceOf(address(caller)), 0);
      assertEq(token.balanceOf(address(pol.tokenJar)), 0);
    }
  }

  function testReleaseWithWormholeFee() external {
    uint256 wormholeFee = 67;
    uint256 threshold = pol.releaser.threshold();
    uint256 nonce = pol.releaser.nonce();

    uint256 length;
    Currency[] memory assets = new Currency[](length);
    uint256[] memory amounts = defaultAmounts;

    for (uint256 i; i < length; i++) {
      tokens[i].mint(address(pol.tokenJar), amounts[i]);

      assets[i] = Currency.wrap(address(tokens[i]));
    }

    vm.deal(address(caller), wormholeFee);

    pol.wormhole.mockSetMessageFee(wormholeFee);

    pol.uni.mockMint(address(caller), threshold);

    caller.doApproval(address(pol.uni), address(pol.releaser), threshold);

    vm.expectEmit(true, true, true, true, address(pol.uni));
    emit ERC20.Transfer(address(pol.nttManager), address(0x00), threshold);

    caller.doReleaserCall({
      releaser: pol.releaser,
      value: wormholeFee,
      nonce: nonce,
      assets: new Currency[](0),
      receiver: bob
    });

    assertEq(pol.uni.balanceOf(bob), 0);
    assertEq(pol.uni.balanceOf(address(caller)), 0);
    assertEq(pol.uni.balanceOf(address(pol.releaser)), 0);

    for (uint256 i; i < length; i++) {
      MockERC20 token = tokens[i];

      assertEq(token.balanceOf(bob), amounts[i]);
      assertEq(token.balanceOf(address(caller)), 0);
      assertEq(token.balanceOf(address(pol.tokenJar)), 0);
    }

    assertEq(bob.balance, 0);
    assertEq(address(caller).balance, 0);
    assertEq(address(pol.releaser).balance, 0);
    assertEq(address(pol.wormhole).balance, wormholeFee);
  }

  function testReleaseWithWormholeFeeMultipleTransceivers() external {
    uint256 wormholeFee = 67;
    uint256 threshold = pol.releaser.threshold();
    uint256 nonce = pol.releaser.nonce();

    uint256 length;
    Currency[] memory assets = new Currency[](length);
    uint256[] memory amounts = defaultAmounts;

    for (uint256 i; i < length; i++) {
      tokens[i].mint(address(pol.tokenJar), amounts[i]);

      assets[i] = Currency.wrap(address(tokens[i]));
    }

    vm.prank(admin);
    WormholeTransceiver secondTransceiver = WormholeTransceiver(
      address(
        new ERC1967Proxy({
          implementation: address(
            new WormholeTransceiver({
              nttManager: address(pol.nttManager),
              wormholeCoreBridge: address(pol.wormhole),
              _consistencyLevel: 202,
              _customConsistencyLevel: 0,
              _additionalBlocks: 0,
              _customConsistencyLevelAddress: address(0x00)
            })
          ),
          _data: new bytes(0)
        })
      )
    );

    vm.prank(admin);
    secondTransceiver.initialize();

    vm.prank(admin);
    pol.nttManager.setTransceiver({transceiver: address(secondTransceiver)});

    vm.deal(address(caller), wormholeFee * 2);

    pol.wormhole.mockSetMessageFee(wormholeFee);

    pol.uni.mockMint(address(caller), threshold);

    caller.doApproval(address(pol.uni), address(pol.releaser), threshold);

    vm.expectEmit(true, true, true, true, address(pol.uni));
    emit ERC20.Transfer(address(pol.nttManager), address(0x00), threshold);

    caller.doReleaserCall({
      releaser: pol.releaser,
      value: wormholeFee * 2,
      nonce: nonce,
      assets: new Currency[](0),
      receiver: bob
    });

    assertEq(pol.uni.balanceOf(bob), 0);
    assertEq(pol.uni.balanceOf(address(caller)), 0);
    assertEq(pol.uni.balanceOf(address(pol.releaser)), 0);

    for (uint256 i; i < length; i++) {
      MockERC20 token = tokens[i];

      assertEq(token.balanceOf(bob), amounts[i]);
      assertEq(token.balanceOf(address(caller)), 0);
      assertEq(token.balanceOf(address(pol.tokenJar)), 0);
    }

    assertEq(bob.balance, 0);
    assertEq(address(caller).balance, 0);
    assertEq(address(pol.releaser).balance, 0);
    assertEq(address(pol.wormhole).balance, wormholeFee * 2);
  }

  function testReleaseWithWormholeFeeAndRefund() external {
    uint256 wormholeFee = 67;
    uint256 amountPaid = wormholeFee + 2;
    uint256 threshold = pol.releaser.threshold();
    uint256 nonce = pol.releaser.nonce();

    uint256 length;
    Currency[] memory assets = new Currency[](length);
    uint256[] memory amounts = defaultAmounts;

    for (uint256 i; i < length; i++) {
      tokens[i].mint(address(pol.tokenJar), amounts[i]);

      assets[i] = Currency.wrap(address(tokens[i]));
    }

    vm.deal(address(caller), amountPaid);

    pol.wormhole.mockSetMessageFee(wormholeFee);

    pol.uni.mockMint(address(caller), threshold);

    caller.doApproval(address(pol.uni), address(pol.releaser), threshold);

    vm.expectEmit(true, true, true, true, address(pol.uni));
    emit ERC20.Transfer(address(pol.nttManager), address(0x00), threshold);

    caller.doReleaserCall({
      releaser: pol.releaser,
      value: amountPaid,
      nonce: nonce,
      assets: new Currency[](0),
      receiver: bob
    });

    assertEq(pol.uni.balanceOf(bob), 0);
    assertEq(pol.uni.balanceOf(address(caller)), 0);
    assertEq(pol.uni.balanceOf(address(pol.releaser)), 0);

    for (uint256 i; i < length; i++) {
      MockERC20 token = tokens[i];

      assertEq(token.balanceOf(bob), amounts[i]);
      assertEq(token.balanceOf(address(caller)), 0);
      assertEq(token.balanceOf(address(pol.tokenJar)), 0);
    }

    assertEq(bob.balance, 0);
    assertEq(address(caller).balance, amountPaid - wormholeFee);
    assertEq(address(pol.releaser).balance, 0);
    assertEq(address(pol.wormhole).balance, wormholeFee);
  }

  function testReleaseThresholdTrimmedTokenJarKepsDust() external {
    uint256 dust = 1;
    uint256 threshold = defaultThreshold + dust;
    uint256 trimmed = pol.releaser.wormholeTrim(threshold);

    uint256 wormholeFee = pol.wormhole.messageFee();
    uint256 nonce = pol.releaser.nonce();

    vm.prank(admin);
    pol.releaser.setThreshold(threshold);

    pol.uni.mockMint(address(caller), threshold);

    caller.doApproval(address(pol.uni), address(pol.releaser), threshold);

    vm.expectEmit(true, true, true, true, address(pol.uni));
    emit ERC20.Transfer(address(pol.nttManager), address(0x00), trimmed);

    caller.doReleaserCall({
      releaser: pol.releaser,
      value: wormholeFee,
      nonce: nonce,
      assets: new Currency[](0),
      receiver: bob
    });

    assertEq(pol.uni.balanceOf(bob), 0);
    assertEq(pol.uni.balanceOf(address(caller)), 0);
    assertEq(pol.uni.balanceOf(address(pol.releaser)), dust);
  }

  function testReleaseZeroThresholdFails() external {
    uint256 threshold = 0;
    uint256 wormholeFee = pol.wormhole.messageFee();
    uint256 nonce = pol.releaser.nonce();

    vm.prank(admin);
    pol.releaser.setThreshold({_threshold: threshold});

    vm.expectRevert();
    caller.doReleaserCall({
      releaser: pol.releaser,
      value: wormholeFee,
      nonce: nonce,
      assets: new Currency[](0),
      receiver: bob
    });
  }

  function testReleaseWormholeFails() external {
    uint256 threshold = pol.releaser.threshold();
    uint256 wormholeFee = pol.wormhole.messageFee();
    uint256 nonce = pol.releaser.nonce();

    pol.uni.mockMint(address(caller), threshold);

    caller.doApproval(address(pol.uni), address(pol.releaser), threshold);

    pol.wormhole.mockSetShouldThrow(true);

    vm.expectRevert();
    caller.doReleaserCall({
      releaser: pol.releaser,
      value: wormholeFee,
      nonce: nonce,
      assets: new Currency[](0),
      receiver: bob
    });

    assertEq(pol.uni.balanceOf(bob), 0);
    assertEq(pol.uni.balanceOf(address(caller)), threshold);
  }

  function testReleaseRefundFails() external {
    uint256 threshold = pol.releaser.threshold();
    uint256 amountPaid = 1;
    uint256 nonce = pol.releaser.nonce();

    vm.deal(address(caller), amountPaid);

    pol.uni.mockMint(address(caller), threshold);

    caller.doApproval(address(pol.uni), address(pol.releaser), threshold);

    caller.mockSetShouldThrow(true);

    vm.expectRevert();

    caller.doReleaserCall({
      releaser: pol.releaser,
      value: amountPaid,
      nonce: nonce,
      assets: new Currency[](0),
      receiver: bob
    });

    assertEq(pol.uni.balanceOf(bob), 0);
    assertEq(pol.uni.balanceOf(address(caller)), threshold);
    assertEq(pol.uni.balanceOf(address(pol.releaser)), 0);

    assertEq(bob.balance, 0);
    assertEq(address(caller).balance, amountPaid);
    assertEq(address(pol.releaser).balance, 0);
  }

  // stack too deep ( ._.)
  struct FuzzParams {
    uint256[21] assetsAmounts;
    uint256 assetsLength;
    uint256 threshold;
    uint64 wormholeFee;
    uint256 amountPaid;
    uint256 receiverSeed;
    bool shouldWormholeThrow;
    bool shouldCallerRefundThrow;
  }

  function testFuzzRelease(FuzzParams memory fuzz) external {
    // this keeps memory reasonably bounded on assetsAmounts, we dont need to test >21
    fuzz.assetsLength = bound(fuzz.assetsLength, 0, 21);

    // this is because wormhole doesn't support numbers greater than 2^64-1 after they clip the
    // decimals, meaning they're putting an implicit upper bound on transfers enforced in the
    // bit trimming libary:
    //
    // 0 < transfer < 2^64-1 * 1e10
    //
    // aka
    //
    // 0 < transfer < 184467440737095516160000000000
    //
    // since we clip the lower deimals on this threshold
    fuzz.threshold = bound(fuzz.threshold, 0, (uint256(type(uint64).max) + 1) * 1e10 - 1);

    address receiver = vm.addr(uint256(keccak256(abi.encode(fuzz.receiverSeed))));
    uint256 nonce = pol.releaser.nonce();
    uint256 trimmed = pol.releaser.wormholeTrim(fuzz.threshold);
    uint256 dust = fuzz.threshold - trimmed;

    Currency[] memory assets = new Currency[](fuzz.assetsLength);

    for (uint256 i; i < fuzz.assetsLength; i++) {
      uint256 amount = fuzz.assetsAmounts[i];

      bytes32 salt = keccak256(abi.encode(amount, i));

      MockERC20 token = new MockERC20{salt: salt}("67", "67", 18);

      token.mint(address(pol.tokenJar), amount);

      assets[i] = Currency.wrap(address(token));
    }

    vm.prank(admin);
    pol.releaser.setThreshold(fuzz.threshold);

    vm.deal(address(caller), fuzz.amountPaid);

    pol.wormhole.mockSetMessageFee(fuzz.wormholeFee);

    pol.wormhole.mockSetShouldThrow(fuzz.shouldWormholeThrow);

    pol.uni.mockMint(address(caller), fuzz.threshold);

    caller.doApproval(address(pol.uni), address(pol.releaser), fuzz.threshold);

    caller.mockSetShouldThrow(fuzz.shouldCallerRefundThrow);

    bool shouldSucceed = true;

    // if assets length too long, it will fail
    shouldSucceed = shouldSucceed && fuzz.assetsLength <= 20;

    // if trimmed threshold is zero, it will fail
    shouldSucceed = shouldSucceed && trimmed > 0;

    // if wormhole fails, it will fail
    shouldSucceed = shouldSucceed && !fuzz.shouldWormholeThrow;

    // if amountPaid is less than the wormholeFee, it will fail
    shouldSucceed = shouldSucceed && fuzz.amountPaid >= fuzz.wormholeFee;

    // if the amountPaid is greater than the wormholeFee but the caller refund fails,
    // it will fail
    //
    // aka: amountPaid must match wormholeFee OR the caller must not throw
    shouldSucceed =
      shouldSucceed && (fuzz.amountPaid == fuzz.wormholeFee || !fuzz.shouldCallerRefundThrow);

    if (shouldSucceed) {
      vm.expectEmit(true, true, true, true, address(pol.uni));
      emit ERC20.Transfer(address(pol.nttManager), address(0x00), trimmed);
    } else {
      vm.expectRevert();
    }

    caller.doReleaserCall({
      releaser: pol.releaser,
      value: fuzz.amountPaid,
      nonce: nonce,
      assets: assets,
      receiver: receiver
    });

    if (shouldSucceed) {
      assertEq(pol.uni.balanceOf(receiver), 0);
      assertEq(pol.uni.balanceOf(address(caller)), 0);
      assertEq(pol.uni.balanceOf(address(pol.releaser)), dust);

      for (uint256 i; i < fuzz.assetsLength; i++) {
        Currency asset = assets[i];

        assertEq(asset.balanceOf(receiver), fuzz.assetsAmounts[i]);
        assertEq(asset.balanceOf(address(caller)), 0);
        assertEq(asset.balanceOf(address(pol.tokenJar)), 0);
      }

      assertEq(receiver.balance, 0);
      assertEq(address(caller).balance, fuzz.amountPaid - fuzz.wormholeFee);
      assertEq(address(pol.releaser).balance, 0);
      assertEq(address(pol.wormhole).balance, fuzz.wormholeFee);
    } else {
      assertEq(pol.uni.balanceOf(receiver), 0);
      assertEq(pol.uni.balanceOf(address(caller)), fuzz.threshold);
      assertEq(pol.uni.balanceOf(address(pol.releaser)), 0);

      for (uint256 i; i < fuzz.assetsLength; i++) {
        Currency asset = assets[i];

        assertEq(asset.balanceOf(receiver), 0);
        assertEq(asset.balanceOf(address(caller)), 0);
        assertEq(asset.balanceOf(address(pol.tokenJar)), fuzz.assetsAmounts[i]);
      }

      assertEq(receiver.balance, 0);
      assertEq(address(caller).balance, fuzz.amountPaid);
      assertEq(address(pol.releaser).balance, 0);
      assertEq(address(pol.wormhole).balance, 0);
    }
  }

  // -- setup functions --------------------------------------------------------------------------
  //

  function _deploy(Deployment storage net, IManagerBase.Mode mode, uint16 wormholeChainId)
    internal
  {
    net.wormhole = new MockWormhole();
    net.uni = new MockSyntheticNttUni();
    net.nttManager = NttManagerNoRateLimiting(
      address(
        new ERC1967Proxy({
          implementation: address(
            new NttManagerNoRateLimiting({
              _token: address(net.uni), _mode: mode, _chainId: wormholeChainId
            })
          ),
          _data: new bytes(0)
        })
      )
    );
    net.transceiver = WormholeTransceiver(
      address(
        new ERC1967Proxy({
          implementation: address(
            new WormholeTransceiver({
              nttManager: address(net.nttManager),
              wormholeCoreBridge: address(net.wormhole),
              _consistencyLevel: 202,
              _customConsistencyLevel: 0,
              _additionalBlocks: 0,
              _customConsistencyLevelAddress: address(0x00)
            })
          ),
          _data: new bytes(0)
        })
      )
    );

    net.tokenJar = new TokenJar();

    net.releaser = new WormholeReleaser({
      _nttManager: address(net.nttManager),
      _resource: address(net.uni),
      _threshold: defaultThreshold,
      _tokenJar: address(net.tokenJar)
    });

    net.nttManager.initialize();
    net.transceiver.initialize{value: net.wormhole.messageFee()}();
    net.nttManager.setTransceiver({transceiver: address(net.transceiver)});
    net.nttManager.setThreshold({threshold: 1});
    net.tokenJar.setReleaser({_releaser: address(net.releaser)});
    net.uni.setNtt({newNtt: address(net.nttManager)});
    net.releaser.setThresholdSetter({_thresholdSetter: admin});

    NttManagerNoRateLimiting.TransceiverInfo[] memory transceiverInfos =
      net.nttManager.getTransceiverInfo();

    assertEq(net.nttManager.getMode(), uint8(mode));
    assertEq(net.nttManager.token(), address(net.uni));
    assertEq(net.nttManager.getThreshold(), 1);

    assertEq(transceiverInfos.length, 1);
    assertEq(transceiverInfos[0].registered, true);
    assertEq(transceiverInfos[0].enabled, true);
    assertEq(transceiverInfos[0].index, 0);

    assertEq(net.transceiver.nttManager(), address(net.nttManager));
    assertEq(net.transceiver.nttManagerToken(), address(net.uni));
    assertEq(net.transceiver.consistencyLevel(), 202);
    assertEq(net.transceiver.customConsistencyLevel(), 0);
    assertEq(net.transceiver.additionalBlocks(), 0);
    assertEq(net.transceiver.customConsistencyLevelAddress(), address(0x00));
    assertEq(address(net.transceiver.wormhole()), address(net.wormhole));
  }

  function _config(Deployment storage src, Deployment storage dst, uint16 wormholePeerChainId)
    internal
  {
    src.transceiver
      .setWormholePeer({
        peerChainId: wormholePeerChainId, peerContract: addrB32(address(dst.transceiver))
      });

    src.nttManager
      .setPeer({
        peerChainId: wormholePeerChainId,
        peerContract: addrB32(address(dst.nttManager)),
        decimals: 18,
        inboundLimit: 0
      });

    address transceiverPeer = b32Addr(src.transceiver.getWormholePeer(wormholePeerChainId));
    NttManagerNoRateLimiting.NttManagerPeer memory nttManagerPeer =
      src.nttManager.getPeer(wormholePeerChainId);

    assertEq(transceiverPeer, address(dst.transceiver));
    assertEq(b32Addr(nttManagerPeer.peerAddress), address(dst.nttManager));
    assertEq(nttManagerPeer.tokenDecimals, 18);
  }

  function _deployFeeInfra() internal {}

  function addrB32(address addr) internal pure returns (bytes32 b32) {
    assembly {
      b32 := addr
    }
  }

  function b32Addr(bytes32 b32) internal pure returns (address addr) {
    assembly {
      addr := b32
    }
  }
}
