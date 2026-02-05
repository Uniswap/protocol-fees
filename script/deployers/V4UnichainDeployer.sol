// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {V4FeeAdapter} from "../../src/feeAdapters/V4FeeAdapter.sol";
import {IV4FeeAdapter} from "../../src/interfaces/IV4FeeAdapter.sol";
import {IOwned} from "../../src/interfaces/base/IOwned.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

/// @title V4UnichainDeployer
/// @notice Deployment contract for V4FeeAdapter on Unichain
/// @dev Deploys V4FeeAdapter configured to use the existing TokenJar.
///      Uses CREATE2 for deterministic deployment addresses.
/// @custom:security-contact security@uniswap.org
contract V4UnichainDeployer {
  /// @notice The deployed V4FeeAdapter contract instance
  IV4FeeAdapter public immutable V4_FEE_ADAPTER;

  /// @notice The Uniswap V4 PoolManager on Unichain
  IPoolManager public constant POOL_MANAGER = IPoolManager(0x1F98400000000000000000000000000000000004);

  /// @notice UNI Timelock alias address on Unichain
  /// @dev Calculated from the aliasing scheme defined at
  ///      https://docs.optimism.io/concepts/stack/differences#address-aliasing
  ///      targeting 0x1a9C8182C09F50C8318d769245beA52c32BE35BC on mainnet
  address public constant OWNER = 0x2BAD8182C09F50c8318d769245beA52C32Be46CD;

  /// @notice The existing TokenJar deployed by UnichainDeployer
  address public constant TOKEN_JAR = 0xD576BDF6b560079a4c204f7644e556DbB19140b5;

  /// @dev CREATE2 salt for deterministic V4FeeAdapter deployment
  bytes32 constant SALT_V4_FEE_ADAPTER = bytes32(uint256(1));

  /// @notice Deploys the V4FeeAdapter configured for Unichain
  /// @dev Performs the following:
  ///      1. Deploy V4FeeAdapter with OWNER as feeSetter and no initial default fee
  ///      2. Transfer ownership to timelock alias
  ///
  ///      The V4FeeAdapter is deployed with:
  ///      - POOL_MANAGER: Unichain V4 PoolManager
  ///      - TOKEN_JAR: Existing TokenJar
  ///      - feeSetter: Timelock alias (same as owner)
  ///      - defaultFee: 0 (to be set via governance or admin action)
  constructor() {
    /// 1. Deploy the V4FeeAdapter
    V4_FEE_ADAPTER = new V4FeeAdapter{salt: SALT_V4_FEE_ADAPTER}(
      address(POOL_MANAGER),
      TOKEN_JAR,
      OWNER, // feeSetter = timelock alias
      0 // defaultFee = 0 (to be configured separately)
    );

    /// 2. Transfer ownership to the timelock alias
    IOwned(address(V4_FEE_ADAPTER)).transferOwnership(OWNER);
  }
}
