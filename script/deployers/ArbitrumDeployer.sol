// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {ITokenJar} from "../../src/interfaces/ITokenJar.sol";
import {TokenJar} from "../../src/TokenJar.sol";
import {IReleaser} from "../../src/interfaces/IReleaser.sol";
import {IOwned} from "../../src/interfaces/base/IOwned.sol";
import {
  ArbitrumBridgedResourceFirepit
} from "../../src/releasers/ArbitrumBridgedResourceFirepit.sol";

/// @title ArbitrumDeployer
/// @notice Deployer for TokenJar + ArbitrumBridgedResourceFirepit on Arbitrum One
/// @dev Deploys and configures the fee collection system with Arbitrum-specific parameters
contract ArbitrumDeployer {
  ITokenJar public immutable TOKEN_JAR;
  IReleaser public immutable RELEASER;

  bytes32 public constant SALT_TOKEN_JAR = bytes32(uint256(1));
  bytes32 public constant SALT_RELEASER = bytes32(uint256(2));

  /// @notice Deploys TokenJar and ArbitrumBridgedResourceFirepit with the given configuration
  /// @param _resource The bridged UNI token address on Arbitrum (L2)
  /// @param _l1Resource The UNI token address on Ethereum mainnet (L1)
  /// @param _threshold The minimum UNI amount required per release
  /// @param _owner The owner address (typically UNI Timelock alias)
  /// @dev Deployment sequence:
  ///      1. Deploy TokenJar
  ///      2. Deploy ArbitrumBridgedResourceFirepit (Releaser)
  ///      3. Set releaser on TokenJar
  ///      4. Transfer TokenJar ownership to owner
  ///      5. Set thresholdSetter on Releaser to owner
  ///      6. Transfer Releaser ownership to owner
  constructor(address _resource, address _l1Resource, uint256 _threshold, address _owner) {
    require(_resource != address(0), "ArbitrumDeployer: resource is zero address");
    require(_l1Resource != address(0), "ArbitrumDeployer: l1Resource is zero address");
    require(_threshold > 0, "ArbitrumDeployer: threshold must be > 0");
    require(_owner != address(0), "ArbitrumDeployer: owner is zero address");

    /// 1. Deploy the TokenJar
    TOKEN_JAR = new TokenJar{salt: SALT_TOKEN_JAR}();

    /// 2. Deploy the Releaser
    RELEASER = new ArbitrumBridgedResourceFirepit{salt: SALT_RELEASER}(
      _resource, _l1Resource, _threshold, address(TOKEN_JAR)
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
