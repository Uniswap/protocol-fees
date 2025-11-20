// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {V3FeeAdapter} from "./feeAdapters/V3FeeAdapter.sol";
import {ITokenJar} from "./interfaces/ITokenJar.sol";
import {TokenJar} from "./TokenJar.sol";
import {Firepit} from "./releasers/Firepit.sol";
import {IReleaser} from "./interfaces/IReleaser.sol";
import {IV3FeeAdapter} from "./interfaces/IV3FeeAdapter.sol";
import {IOwned} from "./interfaces/base/IOwned.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";

/// @title Deployer
/// @notice A deployment contract for the Uniswap fee collection infrastructure
/// @dev Deploys and configures TokenJar, Firepit Releaser, and V3FeeAdapter contracts
///      in a single transaction with deterministic addresses using CREATE2
/// @custom:security-contact security@uniswap.org
contract Deployer {
  /// @notice The deployed TokenJar contract instance
  /// @dev Immutable reference to the fee collection destination contract
  ITokenJar public immutable TOKEN_JAR;

  /// @notice The deployed Releaser contract instance
  /// @dev Immutable reference to the Firepit releaser contract
  IReleaser public immutable RELEASER;

  /// @notice The deployed V3FeeAdapter contract instance
  /// @dev Immutable reference to the fee adapter for V3 pools
  IV3FeeAdapter public immutable FEE_ADAPTER;

  /// @notice The UNI token address used as the resource token for the releaser
  /// @dev Address of the UNI token on mainnet
  address public constant RESOURCE = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

  /// @notice The initial threshold amount of UNI tokens required for release
  /// @dev Set to 69,420 UNI tokens as the initial release threshold
  uint256 public constant THRESHOLD = 69_420;

  /// @notice The Uniswap V3 Factory contract address
  /// @dev Reference to the mainnet V3 Factory for ownership transfer
  IUniswapV3Factory public constant V3_FACTORY =
    IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

  /// @dev CREATE2 salt for deterministic TokenJar deployment
  bytes32 constant SALT_TOKEN_JAR = 0;

  /// @dev CREATE2 salt for deterministic Releaser deployment
  bytes32 constant SALT_RELEASER = 0;

  /// @dev CREATE2 salt for deterministic FeeAdapter deployment
  bytes32 constant SALT_FEE_ADAPTER = 0;

  /// @notice Deploys and configures the entire fee collection infrastructure
  /// @dev Performs the following operations in sequence:
  ///      TOKEN JAR:
  ///      1. Deploy the TokenJar
  ///      3. Set the releaser on the token jar
  ///      4. Update the owner on the token jar
  ///
  ///      RELEASER:
  ///      2. Deploy the Releaser
  ///      5. Update the thresholdSetter on the releaser to the owner
  ///      6. Update the owner on the releaser
  ///
  ///      FEE_ADAPTER:
  ///      7. Deploy the FeeAdapter
  ///      8. Update the feeSetter to the owner
  ///      9. Store fee tiers (100, 500, 3000, 10000)
  ///      10. Update the owner on the fee adapter
  ///
  ///      All ownership is transferred to the current V3Factory owner
  constructor() {
    address owner = V3_FACTORY.owner();
    /// 1. Deploy the TokenJar.
    TOKEN_JAR = new TokenJar{salt: SALT_TOKEN_JAR}();
    /// 2. Deploy the Releaser.
    RELEASER = new Firepit{salt: SALT_RELEASER}(RESOURCE, THRESHOLD, address(TOKEN_JAR));
    /// 3. Set the releaser on the token jar.
    TOKEN_JAR.setReleaser(address(RELEASER));
    /// 4. Update the owner on the token jar.
    IOwned(address(TOKEN_JAR)).transferOwnership(owner);

    /// 5. Update the thresholdSetter on the releaser to the owner.
    RELEASER.setThresholdSetter(owner);
    /// 6. Update the owner on the releaser.
    IOwned(address(RELEASER)).transferOwnership(owner);

    /// 7. Deploy the FeeAdapter.
    FEE_ADAPTER = new V3FeeAdapter{salt: SALT_FEE_ADAPTER}(address(V3_FACTORY), address(TOKEN_JAR));

    /// 8. Update the feeSetter to the owner.
    FEE_ADAPTER.setFeeSetter(owner);

    /// 9. Store fee tiers.
    FEE_ADAPTER.storeFeeTier(100);
    FEE_ADAPTER.storeFeeTier(500);
    FEE_ADAPTER.storeFeeTier(3000);
    FEE_ADAPTER.storeFeeTier(10_000);

    /// 10. Update the owner on the fee adapter.
    IOwned(address(FEE_ADAPTER)).transferOwnership(owner);
  }
}
