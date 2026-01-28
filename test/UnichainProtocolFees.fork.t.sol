// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {UnichainDeployer} from "../script/deployers/UnichainDeployer.sol";
import {DeployUnichain} from "../script/02_DeployUnichain.s.sol";
import {ITokenJar} from "../src/interfaces/ITokenJar.sol";
import {IReleaser} from "../src/interfaces/IReleaser.sol";
import {IOwned} from "../src/interfaces/base/IOwned.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract UnichainProtocolFeesForkTest is Test {
  UnichainDeployer public deployer;
  DeployUnichain public deployScript;

  ITokenJar public tokenJar;
  IReleaser public releaser;

  address public constant RESOURCE = 0x8f187aA05619a017077f5308904739877ce9eA21; // Native Bridge
  // UNI
  uint256 public constant THRESHOLD = 2000e18;

  // Expected owner address (UNI Timelock alias on Unichain)
  address public constant owner = 0x2BAD8182C09F50c8318d769245beA52C32Be46CD;

  function setUp() public {
    // Fork Unichain
    vm.createSelectFork("unichain");

    // Verify we're on the right chain
    assertEq(block.chainid, 130, "Not on Unichain");

    // Deploy the contracts using UnichainDeployer
    deployer = new UnichainDeployer();
    tokenJar = deployer.TOKEN_JAR();
    releaser = deployer.RELEASER();
  }

  function test_deploymentConfiguration() public view {
    // Test TokenJar deployment and configuration
    assertEq(tokenJar.releaser(), address(releaser), "Incorrect releaser on TokenJar");
    assertEq(IOwned(address(tokenJar)).owner(), owner, "Incorrect owner on TokenJar");

    // Test Releaser deployment and configuration
    assertEq(address(releaser.RESOURCE()), RESOURCE, "Incorrect resource token");
    assertEq(releaser.threshold(), THRESHOLD, "Incorrect threshold");
    assertEq(address(releaser.TOKEN_JAR()), address(tokenJar), "Incorrect TokenJar address");
    assertEq(releaser.thresholdSetter(), owner, "Incorrect threshold setter");
    assertEq(IOwned(address(releaser)).owner(), owner, "Incorrect owner on Releaser");
  }

  function test_sequencerFeesAccumulation() public {
    // Simulate sequencer fees being sent to TokenJar
    uint256 initialBalance = address(tokenJar).balance;

    // Send ETH to TokenJar (simulating sequencer fees)
    uint256 feeAmount = 1 ether;
    vm.deal(address(this), feeAmount);
    (bool success,) = address(tokenJar).call{value: feeAmount}("");
    assertTrue(success, "Failed to send ETH to TokenJar");

    // Verify ETH accumulated in TokenJar
    assertEq(
      address(tokenJar).balance, initialBalance + feeAmount, "ETH not accumulated in TokenJar"
    );
  }

  function test_releaseWithUNIBurn() public {
    // Setup: Send sequencer fees to TokenJar
    uint256 ethAmount = 5 ether;
    vm.deal(address(this), ethAmount);
    (bool success,) = address(tokenJar).call{value: ethAmount}("");
    assertTrue(success, "Failed to send ETH to TokenJar");

    // Deal UNI tokens to the caller for burning
    address caller = address(0x1234);
    deal(RESOURCE, caller, THRESHOLD);
    assertEq(IERC20(RESOURCE).balanceOf(caller), THRESHOLD, "UNI not dealt to caller");

    // Record balances before release
    uint256 recipientBalanceBefore = address(0x5678).balance;
    uint256 tokenJarBalanceBefore = address(tokenJar).balance;
    uint256 uniSupplyBefore = IERC20(RESOURCE).totalSupply();

    // Execute release (burning UNI to release ETH)
    uint256 _nonce = releaser.nonce();
    Currency[] memory currencies = new Currency[](1);
    currencies[0] = Currency.wrap(address(0)); // ETH represented as address(0)

    vm.startPrank(caller);
    IERC20(RESOURCE).approve(address(releaser), THRESHOLD);
    releaser.release(_nonce, currencies, address(0x5678));
    vm.stopPrank();

    // Verify ETH transferred from TokenJar to recipient
    assertEq(address(tokenJar).balance, 0, "TokenJar should be empty");
    assertEq(
      address(0x5678).balance - recipientBalanceBefore,
      tokenJarBalanceBefore,
      "Incorrect ETH transferred to recipient"
    );

    // Verify UNI was burned
    assertEq(
      uniSupplyBefore - IERC20(RESOURCE).totalSupply(), THRESHOLD, "UNI not burned correctly"
    );
  }

  function test_multipleSequencerFeeReleases() public {
    // Test multiple rounds of fee accumulation and release
    address[] memory callers = new address[](3);
    callers[0] = address(0xAAA1);
    callers[1] = address(0xAAA2);
    callers[2] = address(0xAAA3);

    for (uint256 i = 0; i < 3; i++) {
      // Send sequencer fees
      uint256 feeAmount = (i + 1) * 2 ether;
      vm.deal(address(this), feeAmount);
      (bool success,) = address(tokenJar).call{value: feeAmount}("");
      assertTrue(success, "Failed to send ETH to TokenJar");

      // Deal UNI and release
      deal(RESOURCE, callers[i], THRESHOLD);

      uint256 _nonce = releaser.nonce();
      Currency[] memory currencies = new Currency[](1);
      currencies[0] = Currency.wrap(address(0)); // ETH

      vm.startPrank(callers[i]);
      IERC20(RESOURCE).approve(address(releaser), THRESHOLD);

      uint256 recipientBalanceBefore = callers[i].balance;
      releaser.release(_nonce, currencies, callers[i]);

      // Verify release
      assertEq(callers[i].balance - recipientBalanceBefore, feeAmount, "Incorrect ETH released");
      assertEq(address(tokenJar).balance, 0, "TokenJar not emptied");
      vm.stopPrank();
    }
  }

  function test_ownershipTransfer() public {
    // Test that ownership can be transferred by current owner
    address newOwner = address(0x9999);

    // Transfer TokenJar ownership
    vm.prank(owner);
    IOwned(address(tokenJar)).transferOwnership(newOwner);
    assertEq(IOwned(address(tokenJar)).owner(), newOwner, "TokenJar ownership not transferred");

    // Transfer Releaser ownership
    vm.prank(owner);
    IOwned(address(releaser)).transferOwnership(newOwner);
    assertEq(IOwned(address(releaser)).owner(), newOwner, "Releaser ownership not transferred");

    // Transfer threshold setter
    vm.prank(newOwner);
    releaser.setThresholdSetter(newOwner);
    assertEq(releaser.thresholdSetter(), newOwner, "Threshold setter not transferred");
  }

  function test_thresholdUpdate() public {
    // Test that threshold can be updated by thresholdSetter
    uint256 newThreshold = 20_000e18;

    vm.prank(owner);
    releaser.setThreshold(newThreshold);
    assertEq(releaser.threshold(), newThreshold, "Threshold not updated");
  }

  function test_releaserUpdate() public {
    // Test that releaser can be updated on TokenJar
    address newReleaser = address(0x8888);

    vm.prank(owner);
    tokenJar.setReleaser(newReleaser);
    assertEq(tokenJar.releaser(), newReleaser, "Releaser not updated on TokenJar");
  }

  function test_invalidRelease_insufficientUNI() public {
    // Test that release fails without sufficient UNI
    address caller = address(0x7777);

    // Send ETH to TokenJar
    vm.deal(address(this), 1 ether);
    (bool success,) = address(tokenJar).call{value: 1 ether}("");
    assertTrue(success);

    // Give caller less than threshold UNI
    deal(RESOURCE, caller, THRESHOLD - 1);

    uint256 _nonce = releaser.nonce();
    Currency[] memory currencies = new Currency[](1);
    currencies[0] = Currency.wrap(address(0));

    vm.startPrank(caller);
    // max approve, but still revert on insufficient balance
    IERC20(RESOURCE).approve(address(releaser), type(uint256).max);

    // Should revert due to insufficient UNI
    vm.expectRevert(RESOURCE);
    releaser.release(_nonce, currencies, caller);
    vm.stopPrank();
  }

  function test_deploymentAddressDeterminism() public {
    // Test that deployment addresses are deterministic with salt
    UnichainDeployer deployer2 = new UnichainDeployer();

    // Addresses should be different for different deployer instances
    // but the pattern should be consistent
    assertTrue(address(deployer2.TOKEN_JAR()) != address(0), "TokenJar not deployed");
    assertTrue(address(deployer2.RELEASER()) != address(0), "Releaser not deployed");
  }
}

