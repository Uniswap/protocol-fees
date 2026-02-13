// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {ITokenJar} from "../../src/interfaces/ITokenJar.sol";
import {TokenJar} from "../../src/TokenJar.sol";
import {IReleaser} from "../../src/interfaces/IReleaser.sol";
import {IOwned} from "../../src/interfaces/base/IOwned.sol";
import {
  OptimismBridgedResourceFirepit
} from "../../src/releasers/OptimismBridgedResourceFirepit.sol";

/// @title OPStackDeployer
/// @notice Generic deployer for TokenJar + OptimismBridgedResourceFirepit on OP Stack chains
/// @dev Deploys and configures the fee collection system with chain-specific parameters.
///      The `_owner` parameter is expected to be a CrossChainAccount contract address on L2.
///      Governance proposals target these L2 contracts via the standard OP Stack XDM flow:
///      L1 Timelock → L1CrossDomainMessenger.sendMessage(CrossChainAccount, forward(target, data))
///      The CrossChainAccount verifies xDomainMessageSender() == L1 Timelock before forwarding.
///      This provides replayability, gas safety, and consistency with existing Uniswap governance
///      patterns (e.g. the v3 factory fee switch uses the same CrossChainAccount approach).
contract OPStackDeployer {
  error ZeroAddress();
  error ZeroThreshold();

  ITokenJar public immutable TOKEN_JAR;
  IReleaser public immutable RELEASER;

  bytes32 public constant SALT_TOKEN_JAR = bytes32(uint256(1));
  bytes32 public constant SALT_RELEASER = bytes32(uint256(2));

  /// @notice Deploys TokenJar and OptimismBridgedResourceFirepit with the given configuration
  /// @param _resource The bridged UNI token address on this chain
  /// @param _threshold The minimum UNI amount required per release
  /// @param _owner The owner address - should be a CrossChainAccount controlled by the L1 Timelock
  /// @dev Deployment sequence:
  ///      1. Deploy TokenJar
  ///      2. Deploy OptimismBridgedResourceFirepit (Releaser)
  ///      3. Set releaser on TokenJar
  ///      4. Transfer TokenJar ownership to owner
  ///      5. Set thresholdSetter on Releaser to owner
  ///      6. Transfer Releaser ownership to owner
  constructor(address _resource, uint256 _threshold, address _owner) {
    require(_resource != address(0), ZeroAddress());
    require(_threshold > 0, ZeroThreshold());
    require(_owner != address(0), ZeroAddress());

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
  }
}
