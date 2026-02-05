// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {V4FeeAdapter} from "../../src/feeAdapters/V4FeeAdapter.sol";
import {IV4FeeAdapter} from "../../src/interfaces/IV4FeeAdapter.sol";
import {IOwned} from "../../src/interfaces/base/IOwned.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

/// @title V4MainnetDeployer
/// @notice Deployment contract for V4FeeAdapter on Ethereum mainnet
/// @dev Deploys V4FeeAdapter configured to use the existing TokenJar.
///      Uses CREATE2 for deterministic deployment addresses.
/// @custom:security-contact security@uniswap.org
contract V4MainnetDeployer {
  /// @notice The deployed V4FeeAdapter contract instance
  IV4FeeAdapter public immutable V4_FEE_ADAPTER;

  /// @notice The Uniswap V4 PoolManager on mainnet
  IPoolManager public constant POOL_MANAGER = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);

  /// @notice The UNI governance timelock on mainnet
  address public constant TIMELOCK = 0x1a9C8182C09F50C8318d769245beA52c32BE35BC;

  /// @notice The existing TokenJar deployed by MainnetDeployer
  address public constant TOKEN_JAR = 0xf38521f130fcCF29dB1961597bc5d2B60F995f85;

  /// @dev CREATE2 salt for deterministic V4FeeAdapter deployment
  bytes32 constant SALT_V4_FEE_ADAPTER = bytes32(uint256(1));

  /// @notice Deploys the V4FeeAdapter configured for mainnet
  /// @dev Performs the following:
  ///      1. Deploy V4FeeAdapter with timelock as feeSetter and no initial default fee
  ///      2. Transfer ownership to timelock
  ///
  ///      The V4FeeAdapter is deployed with:
  ///      - POOL_MANAGER: Mainnet V4 PoolManager
  ///      - TOKEN_JAR: Existing TokenJar
  ///      - feeSetter: Timelock (same as owner)
  ///      - defaultFee: 0 (to be set via governance proposal)
  constructor() {
    /// 1. Deploy the V4FeeAdapter
    V4_FEE_ADAPTER = new V4FeeAdapter{salt: SALT_V4_FEE_ADAPTER}(
      address(POOL_MANAGER),
      TOKEN_JAR,
      TIMELOCK, // feeSetter = timelock
      0 // defaultFee = 0 (to be configured via proposal)
    );

    /// 2. Transfer ownership to the timelock
    IOwned(address(V4_FEE_ADAPTER)).transferOwnership(TIMELOCK);
  }
}
