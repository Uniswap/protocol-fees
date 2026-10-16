// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {IV4ProtocolFeeRuleset} from "../../src/interfaces/IV4FeePolicy.sol";

/// @notice A mock ruleset. It returns the same fee for all pools, or it reverts for all pools.
contract MockProtocolFeeRuleset is IV4ProtocolFeeRuleset {
  error MockReverted();

  uint24 internal immutable FEE;
  bool internal immutable REVERTS;

  constructor(uint24 fee, bool reverts) {
    FEE = fee;
    REVERTS = reverts;
  }

  function getProtocolFee(PoolKey calldata) external view returns (uint24) {
    if (REVERTS) revert MockReverted();
    return FEE;
  }
}

/// @notice A mock hook that returns a protocol fee. The constructor sets the answers of
/// supportsInterface. Thus, the mock can show a hook that does not support ERC165 or the ruleset
/// interface.
contract MockSelfReportingHook is MockProtocolFeeRuleset, IERC165 {
  bool internal immutable SUPPORTS_ERC165;
  bool internal immutable SUPPORTS_RULESET;

  constructor(uint24 fee, bool reverts, bool supportsERC165, bool supportsRuleset)
    MockProtocolFeeRuleset(fee, reverts)
  {
    SUPPORTS_ERC165 = supportsERC165;
    SUPPORTS_RULESET = supportsRuleset;
  }

  function supportsInterface(bytes4 interfaceId) external view returns (bool) {
    if (interfaceId == type(IERC165).interfaceId) return SUPPORTS_ERC165;
    if (interfaceId == type(IV4ProtocolFeeRuleset).interfaceId) return SUPPORTS_RULESET;
    return false;
  }
}
