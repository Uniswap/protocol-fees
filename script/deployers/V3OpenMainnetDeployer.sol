// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {V3OpenFeeAdapter} from "../../src/feeAdapters/V3OpenFeeAdapter.sol";
import {IV3OpenFeeAdapter} from "../../src/interfaces/IV3OpenFeeAdapter.sol";
import {IOwned} from "../../src/interfaces/base/IOwned.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";

/// @title V3OpenMainnetDeployer
/// @notice Deploys V3OpenFeeAdapter on Ethereum mainnet
/// @dev This adapter uses waterfall fee resolution: pool override → tier default → global
/// default
///      Factory ownership must be transferred separately via governance proposal
contract V3OpenMainnetDeployer {
  /// @notice The deployed V3OpenFeeAdapter contract instance
  IV3OpenFeeAdapter public immutable V3_OPEN_FEE_ADAPTER;

  /// @notice The Uniswap V3 Factory contract address on mainnet
  IUniswapV3Factory public constant V3_FACTORY =
    IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

  /// @notice The UNI Timelock address (owner)
  address public constant TIMELOCK = 0x1a9C8182C09F50C8318d769245beA52c32BE35BC;

  /// @notice The TokenJar address for fee collection
  address public constant TOKEN_JAR = 0xf38521f130fcCF29dB1961597bc5d2B60F995f85;

  // Default fee values matching V3FeeAdapter
  uint8 constant DEFAULT_FEE_100 = 4 << 4 | 4; // 1/4 for 0.01% tier
  uint8 constant DEFAULT_FEE_500 = 4 << 4 | 4; // 1/4 for 0.05% tier
  uint8 constant DEFAULT_FEE_3000 = 6 << 4 | 6; // 1/6 for 0.30% tier
  uint8 constant DEFAULT_FEE_10000 = 6 << 4 | 6; // 1/6 for 1.00% tier

  /// @dev CREATE2 salt for deterministic deployment
  bytes32 public constant SALT_V3_OPEN_FEE_ADAPTER = bytes32(uint256(1));

  /// @notice Deploys and configures V3OpenFeeAdapter
  /// @dev Deployment sequence:
  ///      1. Deploy V3OpenFeeAdapter
  ///      2. Set this contract as feeSetter
  ///      3. Set default fees for each tier
  ///      4. Store fee tiers
  ///      5. Transfer feeSetter to timelock
  ///      6. Transfer ownership to timelock
  ///
  /// NOTE: Factory ownership transfer must happen via governance proposal
  constructor() {
    // 1. Deploy V3OpenFeeAdapter
    V3_OPEN_FEE_ADAPTER =
      new V3OpenFeeAdapter{salt: SALT_V3_OPEN_FEE_ADAPTER}(address(V3_FACTORY), TOKEN_JAR);

    // 2. Set this contract as feeSetter temporarily
    V3_OPEN_FEE_ADAPTER.setFeeSetter(address(this));

    // Set default fee (applied when no tier or pool override is set)
    V3_OPEN_FEE_ADAPTER.setDefaultFee(DEFAULT_FEE_100);

    // 3. Set default fees for each tier
    V3_OPEN_FEE_ADAPTER.setFeeTierDefault(100, DEFAULT_FEE_100);
    V3_OPEN_FEE_ADAPTER.setFeeTierDefault(500, DEFAULT_FEE_500);
    V3_OPEN_FEE_ADAPTER.setFeeTierDefault(3000, DEFAULT_FEE_3000);
    V3_OPEN_FEE_ADAPTER.setFeeTierDefault(10_000, DEFAULT_FEE_10000);

    // 4. Store fee tiers
    V3_OPEN_FEE_ADAPTER.storeFeeTier(100);
    V3_OPEN_FEE_ADAPTER.storeFeeTier(500);
    V3_OPEN_FEE_ADAPTER.storeFeeTier(3000);
    V3_OPEN_FEE_ADAPTER.storeFeeTier(10_000);

    // 5. Transfer feeSetter to timelock
    V3_OPEN_FEE_ADAPTER.setFeeSetter(TIMELOCK);

    // 6. Transfer ownership to timelock
    IOwned(address(V3_OPEN_FEE_ADAPTER)).transferOwnership(TIMELOCK);
  }
}
