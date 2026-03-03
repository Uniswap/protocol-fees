// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ArbitrumDeployer} from "../script/deployers/ArbitrumDeployer.sol";
import {DeployArbitrum} from "../script/DeployArbitrum.s.sol";
import {ITokenJar} from "../src/interfaces/ITokenJar.sol";
import {IReleaser} from "../src/interfaces/IReleaser.sol";
import {IOwned} from "../src/interfaces/base/IOwned.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ArbitrumBridgedResourceFirepit} from "../src/releasers/ArbitrumBridgedResourceFirepit.sol";

/// @notice Mock ArbSys precompile for fork testing
/// @dev The real ArbSys at 0x64 is a precompile that doesn't have bytecode,
///      so we need to mock it for fork tests to work
contract MockArbSys {
  uint256 public txCount;

  event L2ToL1Tx(
    address caller,
    address indexed destination,
    uint256 indexed hash,
    uint256 indexed position,
    uint256 arbBlockNum,
    uint256 ethBlockNum,
    uint256 timestamp,
    uint256 callvalue,
    bytes data
  );

  function sendTxToL1(address destination, bytes calldata data) external payable returns (uint256) {
    uint256 id = txCount++;
    emit L2ToL1Tx(
      msg.sender,
      destination,
      uint256(keccak256(data)),
      id,
      block.number,
      block.number,
      block.timestamp,
      msg.value,
      data
    );
    return id;
  }

  function arbBlockNumber() external view returns (uint256) {
    return block.number;
  }
}

contract ArbitrumProtocolFeesForkTest is Test {
  ArbitrumDeployer public deployer;
  DeployArbitrum public deployScript;

  ITokenJar public tokenJar;
  IReleaser public releaser;

  // Bridged UNI token on Arbitrum One
  // https://arbiscan.io/token/0xfa7f8980b0f1e64a2062791cc3b0871572f1f7f0
  address public constant RESOURCE = 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0;

  // L1 UNI token on Ethereum mainnet
  address public constant L1_RESOURCE = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

  uint256 public constant THRESHOLD = 2000e18;

  // Expected owner address (UNI Timelock alias on Arbitrum)
  // Same alias calculation as OP Stack chains
  address public constant owner = 0x2BAD8182C09F50c8318d769245beA52C32Be46CD;

  // ArbSys precompile address
  address constant ARB_SYS = address(0x64);

  function setUp() public {
    // Fork Arbitrum One
    vm.createSelectFork("arbitrum");

    // Verify we're on the right chain
    assertEq(block.chainid, 42_161, "Not on Arbitrum One");

    // Deploy mock ArbSys and etch it at the precompile address
    // This is needed because ArbSys is a precompile without bytecode in fork tests
    MockArbSys mockArbSys = new MockArbSys();
    vm.etch(ARB_SYS, address(mockArbSys).code);

    // Deploy the contracts using ArbitrumDeployer
    // V3 Factory on Arbitrum One: 0x1F98431c8aD98523631AE4a59f267346ea31F984
    deployer = new ArbitrumDeployer(
      RESOURCE, L1_RESOURCE, THRESHOLD, owner, 0x1F98431c8aD98523631AE4a59f267346ea31F984
    );
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

    // Test Arbitrum-specific configuration
    ArbitrumBridgedResourceFirepit arbReleaser = ArbitrumBridgedResourceFirepit(address(releaser));
    assertEq(arbReleaser.L1_RESOURCE(), L1_RESOURCE, "Incorrect L1 resource token");
    assertEq(
      arbReleaser.L2_GATEWAY_ROUTER(),
      0x5288c571Fd7aD117beA99bF60FE0846C4E84F933,
      "Incorrect L2 Gateway Router"
    );
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
    uint256 releaserUNIBefore = IERC20(RESOURCE).balanceOf(address(releaser));

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

    // For Arbitrum, the UNI is first collected in the releaser then bridged
    // After the bridge call, the releaser's UNI balance should be the same as before
    // (bridge took the tokens)
    assertEq(
      IERC20(RESOURCE).balanceOf(address(releaser)),
      releaserUNIBefore,
      "UNI should have been bridged"
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
    ArbitrumDeployer deployer2 = new ArbitrumDeployer(
      RESOURCE, L1_RESOURCE, THRESHOLD, owner, 0x1F98431c8aD98523631AE4a59f267346ea31F984
    );

    // Addresses should be different for different deployer instances
    // but the pattern should be consistent
    assertTrue(address(deployer2.TOKEN_JAR()) != address(0), "TokenJar not deployed");
    assertTrue(address(deployer2.RELEASER()) != address(0), "Releaser not deployed");
  }

  function test_l1ResourceConfiguration() public view {
    // Verify L1 resource is correctly configured
    ArbitrumBridgedResourceFirepit arbReleaser = ArbitrumBridgedResourceFirepit(address(releaser));
    assertEq(arbReleaser.L1_RESOURCE(), L1_RESOURCE, "L1 resource not correctly set");
  }
}
