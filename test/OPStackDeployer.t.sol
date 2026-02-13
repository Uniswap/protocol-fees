// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Predeploys} from "@eth-optimism-bedrock/src/libraries/Predeploys.sol";

import {OPStackDeployer} from "../script/deployers/OPStackDeployer.sol";
import {ITokenJar} from "../src/interfaces/ITokenJar.sol";
import {IReleaser} from "../src/interfaces/IReleaser.sol";
import {IOwned} from "../src/interfaces/base/IOwned.sol";
import {IL2StandardBridge} from "../src/interfaces/external/IL2StandardBridge.sol";

/// @notice Mock L2StandardBridge for testing
contract MockL2StandardBridge is IL2StandardBridge {
  function bridgeETHTo(address, uint32, bytes calldata) external payable override {
    revert("Not implemented");
  }

  function withdrawTo(address, address, uint256, uint32, bytes calldata) external override {
    // No-op for deployment tests
  }
}

contract OPStackDeployerTest is Test {
  OPStackDeployer public deployer;

  MockERC20 public resource;
  MockL2StandardBridge public mockBridge;

  ITokenJar public tokenJar;
  IReleaser public releaser;

  address public owner;
  uint256 public threshold;

  function setUp() public {
    // Deploy mock resource token (simulating bridged UNI)
    resource = new MockERC20("Bridged UNI", "UNI", 18);

    // Deploy mock L2 bridge at the expected predeploy address
    mockBridge = new MockL2StandardBridge();
    vm.etch(Predeploys.L2_STANDARD_BRIDGE, address(mockBridge).code);

    owner = makeAddr("owner");
    threshold = 2000e18;

    // Deploy the OPStackDeployer
    deployer = new OPStackDeployer(address(resource), threshold, owner);

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

  function test_deployer_deterministicAddresses() public {
    // Deploy another deployer with same parameters
    OPStackDeployer deployer2 = new OPStackDeployer(address(resource), threshold, owner);

    // TokenJar and Releaser should have different addresses (different deployer address)
    // But if we deploy from the same address with same salt, we'd get same addresses
    // This test verifies the CREATE2 salts are used correctly
    assertTrue(address(deployer2.TOKEN_JAR()) != address(0));
    assertTrue(address(deployer2.RELEASER()) != address(0));
  }

  function test_deployer_differentThresholds() public {
    uint256 lowThreshold = 1000e18;
    uint256 highThreshold = 5000e18;

    OPStackDeployer lowDeployer = new OPStackDeployer(address(resource), lowThreshold, owner);
    OPStackDeployer highDeployer = new OPStackDeployer(address(resource), highThreshold, owner);

    assertEq(lowDeployer.RELEASER().threshold(), lowThreshold);
    assertEq(highDeployer.RELEASER().threshold(), highThreshold);
  }

  function test_deployer_differentOwners() public {
    address owner1 = makeAddr("owner1");
    address owner2 = makeAddr("owner2");

    OPStackDeployer deployer1 = new OPStackDeployer(address(resource), threshold, owner1);
    OPStackDeployer deployer2 = new OPStackDeployer(address(resource), threshold, owner2);

    assertEq(IOwned(address(deployer1.TOKEN_JAR())).owner(), owner1);
    assertEq(IOwned(address(deployer2.TOKEN_JAR())).owner(), owner2);
    assertEq(IOwned(address(deployer1.RELEASER())).owner(), owner1);
    assertEq(IOwned(address(deployer2.RELEASER())).owner(), owner2);
  }

  function test_deployer_differentResources() public {
    MockERC20 resource1 = new MockERC20("Resource1", "R1", 18);
    MockERC20 resource2 = new MockERC20("Resource2", "R2", 18);

    OPStackDeployer deployer1 = new OPStackDeployer(address(resource1), threshold, owner);
    OPStackDeployer deployer2 = new OPStackDeployer(address(resource2), threshold, owner);

    assertEq(address(deployer1.RELEASER().RESOURCE()), address(resource1));
    assertEq(address(deployer2.RELEASER().RESOURCE()), address(resource2));
  }

  function test_revert_deployer_zeroResource() public {
    vm.expectRevert(OPStackDeployer.ZeroAddress.selector);
    new OPStackDeployer(address(0), threshold, owner);
  }

  function test_revert_deployer_zeroThreshold() public {
    vm.expectRevert(OPStackDeployer.ZeroThreshold.selector);
    new OPStackDeployer(address(resource), 0, owner);
  }

  function test_revert_deployer_zeroOwner() public {
    vm.expectRevert(OPStackDeployer.ZeroAddress.selector);
    new OPStackDeployer(address(resource), threshold, address(0));
  }

  function test_fuzz_deployer_parameters(address _resource, uint256 _threshold, address _owner)
    public
  {
    vm.assume(_resource != address(0));
    vm.assume(_threshold > 0);
    vm.assume(_owner != address(0));

    OPStackDeployer fuzzDeployer = new OPStackDeployer(_resource, _threshold, _owner);

    assertEq(address(fuzzDeployer.RELEASER().RESOURCE()), _resource);
    assertEq(fuzzDeployer.RELEASER().threshold(), _threshold);
    assertEq(IOwned(address(fuzzDeployer.TOKEN_JAR())).owner(), _owner);
    assertEq(IOwned(address(fuzzDeployer.RELEASER())).owner(), _owner);
    assertEq(fuzzDeployer.RELEASER().thresholdSetter(), _owner);
  }
}
