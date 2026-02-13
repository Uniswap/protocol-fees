// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {OPStackDeployer} from "./deployers/OPStackDeployer.sol";
import {CrossChainAccount, IMessenger} from "./CrossChainAccount.sol";
import {IOwned} from "../src/interfaces/base/IOwned.sol";
import {IResourceManager} from "../src/interfaces/base/IResourceManager.sol";

interface IOptimismMintableERC20Factory {
  function createOptimismMintableERC20(
    address _remoteToken,
    string memory _name,
    string memory _symbol
  ) external returns (address);
}

/// @title DeployOPStackChain
/// @notice Abstract base for deploying TokenJar + OptimismBridgedResourceFirepit on any OP Stack
/// chain @dev Concrete scripts override `_chainId()`, `_resource()`, and `_name()`.
///      THRESHOLD is shared across all OP Stack deployments.
///      If `_resource()` returns address(0), the script first creates a canonical bridged UNI token
///      via the OptimismMintableERC20Factory predeploy before proceeding with deployment.
///      Ownership is delegated to a CrossChainAccount contract, which authenticates governance
///      messages via the L2CrossDomainMessenger + xDomainMessageSender check. Chains that already
///      have a CrossChainAccount (e.g. OP Mainnet, Base) can override `_owner()` to reuse it.
abstract contract DeployOPStackChain is Script {
  error WrongChain();
  // UNI threshold for release
  uint256 public constant THRESHOLD = 2000e18;

  // L1 UNI Timelock (the real L1 address, NOT aliased)
  address public constant L1_TIMELOCK = 0x1a9C8182C09F50C8318d769245beA52c32BE35BC;

  // OP Stack predeploy: L2CrossDomainMessenger
  address public constant L2_MESSENGER = 0x4200000000000000000000000000000000000007;

  // L1 UNI token address
  address public constant L1_UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

  // OP Stack predeploy: OptimismMintableERC20Factory
  IOptimismMintableERC20Factory public constant OP_STACK_ERC20_FACTORY =
    IOptimismMintableERC20Factory(0x4200000000000000000000000000000000000012);

  /// @notice The chain ID of the chain to deploy to
  /// @dev Concrete scripts override this function to return the chain ID of the chain to deploy to
  function _chainId() internal pure virtual returns (uint256);

  /// @notice The address of the resource token (typically the bridged UNI token)
  /// @dev If `_resource()` returns address(0), the script first creates a canonical bridged UNI
  /// token via the OptimismMintableERC20Factory predeploy before proceeding with deployment.
  /// @dev Concrete scripts override this function to return the address of the resource token
  function _resource() internal pure virtual returns (address);

  /// @notice The name of the chain
  /// @dev Concrete scripts override this function to return the name of the chain
  function _name() internal pure virtual returns (string memory);

  /// @notice Returns the owner address for the deployed contracts
  /// @dev Default implementation deploys a new CrossChainAccount that authenticates governance
  ///      messages via L2CrossDomainMessenger.xDomainMessageSender() == L1_TIMELOCK.
  ///      Override for chains that already have a CrossChainAccount (e.g. OP Mainnet, Base).
  function _owner() internal virtual returns (address) {
    CrossChainAccount xAccount =
      new CrossChainAccount{salt: bytes32(uint256(1))}(IMessenger(L2_MESSENGER), L1_TIMELOCK);
    console2.log("CrossChainAccount:", address(xAccount));
    return address(xAccount);
  }

  /// @notice Creates a canonical bridged UNI token via the OptimismMintableERC20Factory predeploy
  /// @dev Concrete scripts can override this function to create the resource token differently if
  /// needed. @return resource The address of the created bridged UNI token
  function _createBridgedUNI() internal virtual returns (address resource) {
    resource = OP_STACK_ERC20_FACTORY.createOptimismMintableERC20(L1_UNI, "Uniswap", "UNI");
    console2.log("Created bridged UNI:", resource);
    return resource;
  }

  function setUp() public {}

  function run() public {
    require(block.chainid == _chainId(), WrongChain());

    console2.log(string.concat("=== ", _name(), " Deployment ==="));
    vm.startBroadcast();

    address owner = _owner();

    address resource = _resource();
    if (resource == address(0)) resource = _createBridgedUNI();

    OPStackDeployer deployer =
      new OPStackDeployer{salt: bytes32(uint256(1))}(resource, THRESHOLD, owner);

    console2.log("Deployer:", address(deployer));
    console2.log("TOKEN_JAR:", address(deployer.TOKEN_JAR()));
    console2.log("RELEASER:", address(deployer.RELEASER()));

    vm.stopBroadcast();

    // Post-deployment assertions
    assert(deployer.TOKEN_JAR().releaser() == address(deployer.RELEASER()));
    assert(IOwned(address(deployer.TOKEN_JAR())).owner() == owner);
    assert(IResourceManager(address(deployer.RELEASER())).thresholdSetter() == owner);
    assert(IOwned(address(deployer.RELEASER())).owner() == owner);
  }
}
