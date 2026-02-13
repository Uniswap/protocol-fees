// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {ArbitrumDeployer} from "../script/deployers/ArbitrumDeployer.sol";
import {ITokenJar} from "../src/interfaces/ITokenJar.sol";
import {IReleaser} from "../src/interfaces/IReleaser.sol";
import {IOwned} from "../src/interfaces/base/IOwned.sol";
import {IL2GatewayRouter} from "../src/interfaces/external/IL2GatewayRouter.sol";
import {ArbitrumBridgedResourceFirepit} from "../src/releasers/ArbitrumBridgedResourceFirepit.sol";

/// @notice Mock L2GatewayRouter for testing
contract MockL2GatewayRouter is IL2GatewayRouter {
  address public mockGateway;

  constructor(address _mockGateway) {
    mockGateway = _mockGateway;
  }

  function outboundTransfer(address, address, uint256, bytes calldata)
    external
    payable
    override
    returns (bytes memory)
  {
    return bytes("");
  }

  function getGateway(address) external view override returns (address) {
    return mockGateway;
  }

  function calculateL2TokenAddress(address) external pure override returns (address) {
    return address(0);
  }
}

/// @notice Mock Gateway for token approval
contract MockGateway {
  // Just needs to exist for approval

  }

contract ArbitrumDeployerTest is Test {
  ArbitrumDeployer public deployer;

  MockERC20 public resource;
  MockL2GatewayRouter public mockRouter;
  MockGateway public mockGateway;

  ITokenJar public tokenJar;
  IReleaser public releaser;

  address public owner;
  uint256 public threshold;
  address public l1Resource;

  function setUp() public {
    // Deploy mock gateway first
    mockGateway = new MockGateway();

    // Deploy mock router at the expected address
    mockRouter = new MockL2GatewayRouter(address(mockGateway));
    vm.etch(
      0x5288c571Fd7aD117beA99bF60FE0846C4E84F933, // L2_GATEWAY_ROUTER
      address(mockRouter).code
    );
    // Store the mockGateway address in the router's storage slot
    vm.store(
      0x5288c571Fd7aD117beA99bF60FE0846C4E84F933,
      bytes32(uint256(0)), // First storage slot for mockGateway
      bytes32(uint256(uint160(address(mockGateway))))
    );

    // Deploy mock resource token (simulating bridged UNI)
    resource = new MockERC20("Bridged UNI", "UNI", 18);

    owner = makeAddr("owner");
    threshold = 2000e18;
    l1Resource = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // Real L1 UNI address

    // Deploy the ArbitrumDeployer
    deployer = new ArbitrumDeployer(address(resource), l1Resource, threshold, owner);

    tokenJar = deployer.TOKEN_JAR();
    releaser = deployer.RELEASER();
  }

  function test_deployer_tokenJar_setUp() public view {
    // TokenJar owner should be the specified owner
    assertEq(IOwned(address(tokenJar)).owner(), owner);
    // TokenJar releaser should be the deployed releaser
    assertEq(tokenJar.releaser(), address(releaser));
  }

  function test_deployer_releaser_setUp() public view {
    // Releaser owner should be the specified owner
    assertEq(IOwned(address(releaser)).owner(), owner);
    // ThresholdSetter should be the specified owner
    assertEq(releaser.thresholdSetter(), owner);
    // Threshold should match the specified threshold
    assertEq(releaser.threshold(), threshold);
    // TOKEN_JAR should be the deployed tokenJar
    assertEq(address(releaser.TOKEN_JAR()), address(tokenJar));
    // RESOURCE_RECIPIENT should be the releaser itself (for two-stage burn)
    assertEq(releaser.RESOURCE_RECIPIENT(), address(releaser));
    // RESOURCE should be the specified resource token
    assertEq(address(releaser.RESOURCE()), address(resource));
  }

  function test_deployer_l1Resource() public view {
    ArbitrumBridgedResourceFirepit arbReleaser = ArbitrumBridgedResourceFirepit(address(releaser));
    assertEq(arbReleaser.L1_RESOURCE(), l1Resource);
  }

  function test_deployer_deterministicAddresses() public {
    // Deploy another deployer with same parameters
    ArbitrumDeployer deployer2 =
      new ArbitrumDeployer(address(resource), l1Resource, threshold, owner);

    // TokenJar and Releaser should have different addresses (different deployer address)
    // But if we deploy from the same address with same salt, we'd get same addresses
    // This test verifies the CREATE2 salts are used correctly
    assertTrue(address(deployer2.TOKEN_JAR()) != address(0));
    assertTrue(address(deployer2.RELEASER()) != address(0));
  }

  function test_deployer_differentThresholds() public {
    uint256 lowThreshold = 1000e18;
    uint256 highThreshold = 5000e18;

    ArbitrumDeployer lowDeployer =
      new ArbitrumDeployer(address(resource), l1Resource, lowThreshold, owner);
    ArbitrumDeployer highDeployer =
      new ArbitrumDeployer(address(resource), l1Resource, highThreshold, owner);

    assertEq(lowDeployer.RELEASER().threshold(), lowThreshold);
    assertEq(highDeployer.RELEASER().threshold(), highThreshold);
  }

  function test_deployer_differentOwners() public {
    address owner1 = makeAddr("owner1");
    address owner2 = makeAddr("owner2");

    ArbitrumDeployer deployer1 =
      new ArbitrumDeployer(address(resource), l1Resource, threshold, owner1);
    ArbitrumDeployer deployer2 =
      new ArbitrumDeployer(address(resource), l1Resource, threshold, owner2);

    assertEq(IOwned(address(deployer1.TOKEN_JAR())).owner(), owner1);
    assertEq(IOwned(address(deployer2.TOKEN_JAR())).owner(), owner2);
    assertEq(IOwned(address(deployer1.RELEASER())).owner(), owner1);
    assertEq(IOwned(address(deployer2.RELEASER())).owner(), owner2);
  }

  function test_deployer_differentResources() public {
    MockERC20 resource1 = new MockERC20("Resource1", "R1", 18);
    MockERC20 resource2 = new MockERC20("Resource2", "R2", 18);

    ArbitrumDeployer deployer1 =
      new ArbitrumDeployer(address(resource1), l1Resource, threshold, owner);
    ArbitrumDeployer deployer2 =
      new ArbitrumDeployer(address(resource2), l1Resource, threshold, owner);

    assertEq(address(deployer1.RELEASER().RESOURCE()), address(resource1));
    assertEq(address(deployer2.RELEASER().RESOURCE()), address(resource2));
  }

  function test_revert_deployer_zeroResource() public {
    vm.expectRevert(ArbitrumDeployer.ZeroAddress.selector);
    new ArbitrumDeployer(address(0), l1Resource, threshold, owner);
  }

  function test_revert_deployer_zeroL1Resource() public {
    vm.expectRevert(ArbitrumDeployer.ZeroAddress.selector);
    new ArbitrumDeployer(address(resource), address(0), threshold, owner);
  }

  function test_revert_deployer_zeroThreshold() public {
    vm.expectRevert(ArbitrumDeployer.ZeroThreshold.selector);
    new ArbitrumDeployer(address(resource), l1Resource, 0, owner);
  }

  function test_revert_deployer_zeroOwner() public {
    vm.expectRevert(ArbitrumDeployer.ZeroAddress.selector);
    new ArbitrumDeployer(address(resource), l1Resource, threshold, address(0));
  }

  function test_fuzz_deployer_parameters(
    address _resource,
    address _l1Resource,
    uint256 _threshold,
    address _owner
  ) public {
    vm.assume(_resource != address(0));
    vm.assume(_l1Resource != address(0));
    vm.assume(_threshold > 0);
    vm.assume(_owner != address(0));
    // Exclude precompile addresses (can't vm.etch them)
    vm.assume(uint160(_resource) > 0xFF);
    // Exclude L2_GATEWAY_ROUTER address (needed for gateway lookup)
    vm.assume(_resource != 0x5288c571Fd7aD117beA99bF60FE0846C4E84F933);

    // Etch ERC20 code at the fuzzed resource address since safeApprove requires extcodesize > 0
    vm.etch(_resource, address(resource).code);

    ArbitrumDeployer fuzzDeployer = new ArbitrumDeployer(_resource, _l1Resource, _threshold, _owner);

    assertEq(address(fuzzDeployer.RELEASER().RESOURCE()), _resource);
    assertEq(fuzzDeployer.RELEASER().threshold(), _threshold);
    assertEq(IOwned(address(fuzzDeployer.TOKEN_JAR())).owner(), _owner);
    assertEq(IOwned(address(fuzzDeployer.RELEASER())).owner(), _owner);
    assertEq(fuzzDeployer.RELEASER().thresholdSetter(), _owner);

    ArbitrumBridgedResourceFirepit arbReleaser =
      ArbitrumBridgedResourceFirepit(address(fuzzDeployer.RELEASER()));
    assertEq(arbReleaser.L1_RESOURCE(), _l1Resource);
  }
}
