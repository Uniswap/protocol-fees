// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {ITokenJar} from "../../src/interfaces/ITokenJar.sol";
import {TokenJar} from "../../src/TokenJar.sol";
import {IReleaser} from "../../src/interfaces/IReleaser.sol";
import {IV3OpenFeeAdapter} from "../../src/interfaces/IV3OpenFeeAdapter.sol";
import {V3OpenFeeAdapter} from "../../src/feeAdapters/V3OpenFeeAdapter.sol";
import {IOwned} from "../../src/interfaces/base/IOwned.sol";
import {
  OptimismBridgedResourceFirepit
} from "../../src/releasers/OptimismBridgedResourceFirepit.sol";

/// @title OPStackDeployer
/// @notice Generic deployer for TokenJar + OptimismBridgedResourceFirepit + V3OpenFeeAdapter
///         on OP Stack chains
/// @dev Deploys and configures the fee collection system with chain-specific parameters.
///      The `_owner` parameter is expected to be a CrossChainAccount contract address on L2.
///      Governance proposals target these L2 contracts via the standard OP Stack XDM flow:
///      L1 Timelock → L1CrossDomainMessenger.sendMessage(CrossChainAccount, forward(target,
/// data))
///      The CrossChainAccount verifies xDomainMessageSender() == L1 Timelock before forwarding.
///      This provides replayability, gas safety, and consistency with existing Uniswap governance
///      patterns (e.g. the v3 factory fee switch uses the same CrossChainAccount approach).
///
contract OPStackDeployer {
  error ZeroAddress();
  error ZeroThreshold();

  ITokenJar public immutable TOKEN_JAR;
  IReleaser public immutable RELEASER;
  IV3OpenFeeAdapter public immutable V3_OPEN_FEE_ADAPTER;

  bytes32 public constant SALT_TOKEN_JAR = bytes32(uint256(1));
  bytes32 public constant SALT_RELEASER = bytes32(uint256(2));
  bytes32 public constant SALT_FEE_ADAPTER = bytes32(uint256(3));

  // Protocol fee defaults — same as mainnet
  uint8 constant DEFAULT_FEE_100 = 4 << 4 | 4; // 1/4 for 0.01% tier
  uint8 constant DEFAULT_FEE_500 = 4 << 4 | 4; // 1/4 for 0.05% tier
  uint8 constant DEFAULT_FEE_3000 = 6 << 4 | 6; // 1/6 for 0.30% tier
  uint8 constant DEFAULT_FEE_10000 = 6 << 4 | 6; // 1/6 for 1.00% tier

  /// @notice Deploys TokenJar, OptimismBridgedResourceFirepit, and V3OpenFeeAdapter
  /// @param _resource The bridged UNI token address on this chain
  /// @param _threshold The minimum UNI amount required per release
  /// @param _owner The owner address - should be a CrossChainAccount controlled by the L1 Timelock
  /// @param _v3Factory The Uniswap V3 Factory address on this chain
  constructor(address _resource, uint256 _threshold, address _owner, address _v3Factory) {
    require(_resource != address(0), ZeroAddress());
    require(_threshold > 0, ZeroThreshold());
    require(_owner != address(0), ZeroAddress());
    require(_v3Factory != address(0), ZeroAddress());

    /// 1. Deploy the TokenJar
    TOKEN_JAR = new TokenJar{salt: SALT_TOKEN_JAR}();

    /// 2. Deploy the Releaser
    RELEASER = new OptimismBridgedResourceFirepit{salt: SALT_RELEASER}(
      _resource, _threshold, address(TOKEN_JAR)
    );

    /// 3. Set the releaser on the token jar
    TOKEN_JAR.setReleaser(address(RELEASER));

    /// 4. Update the owner on the token jar
    IOwned(address(TOKEN_JAR)).transferOwnership(_owner);

    /// 5. Update the thresholdSetter on the releaser to the owner
    RELEASER.setThresholdSetter(_owner);

    /// 6. Update the owner on the releaser
    IOwned(address(RELEASER)).transferOwnership(_owner);

    /// 7. Deploy and configure V3OpenFeeAdapter
    V3OpenFeeAdapter feeAdapter =
      new V3OpenFeeAdapter{salt: SALT_FEE_ADAPTER}(_v3Factory, address(TOKEN_JAR));

    // Configure fee tier defaults
    feeAdapter.setFeeSetter(address(this));

    // Set default fee (applied when no tier or pool override is set)
    feeAdapter.setDefaultFee(DEFAULT_FEE_100);

    // Set fee tier defaults
    feeAdapter.setFeeTierDefault(100, DEFAULT_FEE_100);
    feeAdapter.setFeeTierDefault(500, DEFAULT_FEE_500);
    feeAdapter.setFeeTierDefault(3000, DEFAULT_FEE_3000);
    feeAdapter.setFeeTierDefault(10_000, DEFAULT_FEE_10000);

    // Store fee tiers
    feeAdapter.storeFeeTier(100);
    feeAdapter.storeFeeTier(500);
    feeAdapter.storeFeeTier(3000);
    feeAdapter.storeFeeTier(10_000);

    // Transfer feeSetter and ownership to CrossChainAccount
    feeAdapter.setFeeSetter(_owner);
    feeAdapter.transferOwnership(_owner);

    V3_OPEN_FEE_ADAPTER = IV3OpenFeeAdapter(address(feeAdapter));
  }
}
