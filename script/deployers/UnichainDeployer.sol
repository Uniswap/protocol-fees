// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {ITokenJar} from "../../src/interfaces/ITokenJar.sol";
import {TokenJar} from "../../src/TokenJar.sol";
import {IReleaser} from "../../src/interfaces/IReleaser.sol";
import {IOwned} from "../../src/interfaces/base/IOwned.sol";
import {
  OptimismBridgedResourceFirepit
} from "../../src/releasers/OptimismBridgedResourceFirepit.sol";

contract UnichainDeployer {
  ITokenJar public immutable TOKEN_JAR;
  IReleaser public immutable RELEASER;

  // Native Bridge UNI
  address public constant RESOURCE = 0x8f187aA05619a017077f5308904739877ce9eA21;
  uint256 public constant THRESHOLD = 2000e18;
  // UNI Timelock alias address on Unichain
  // Calculated from the aliasing scheme defined here
  // https://docs.optimism.io/concepts/stack/differences#address-aliasing
  // targeting 0x1a9C8182C09F50C8318d769245beA52c32BE35BC on mainnet
  address public constant OWNER = 0x2BAD8182C09F50c8318d769245beA52C32Be46CD;

  bytes32 constant SALT_TOKEN_JAR = bytes32(uint256(1));
  bytes32 constant SALT_RELEASER = bytes32(uint256(2));

  //// TOKEN JAR:
  /// 1. Deploy the TokenJar
  /// 3. Set the releaser on the token jar.
  /// 4. Update the owner on the token jar.

  /// RELEASER:
  /// 2. Deploy the Releaser.
  /// 5. Update the thresholdSetter on the releaser to the owner.
  /// 6. Update the owner on the releaser.
  constructor() {
    /// 1. Deploy the TokenJar.
    TOKEN_JAR = new TokenJar{salt: SALT_TOKEN_JAR}();
    /// 2. Deploy the Releaser.
    RELEASER = new OptimismBridgedResourceFirepit{salt: SALT_RELEASER}(
      RESOURCE, THRESHOLD, address(TOKEN_JAR)
    );
    /// 3. Set the releaser on the token jar.
    TOKEN_JAR.setReleaser(address(RELEASER));
    /// 4. Update the owner on the token jar.
    IOwned(address(TOKEN_JAR)).transferOwnership(OWNER);

    /// 5. Update the thresholdSetter on the releaser to the owner.
    RELEASER.setThresholdSetter(OWNER);
    /// 6. Update the owner on the releaser.
    IOwned(address(RELEASER)).transferOwnership(OWNER);
  }
}
