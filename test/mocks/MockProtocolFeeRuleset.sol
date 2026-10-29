// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
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

/// @notice A mock ruleset whose fee is linear in the LP fee: `betaPips * lpFee / 1_000_000` in each
/// direction, capped at MAX_PROTOCOL_FEE. It stands in for a static curve with one bucket at floor
/// 0.
contract MockLinearRuleset is IV4ProtocolFeeRuleset {
  uint32 public betaPips;

  function setBetaPips(uint32 _betaPips) external {
    betaPips = _betaPips;
  }

  function getProtocolFee(PoolKey calldata key) external view returns (uint24) {
    uint256 perDirection = uint256(betaPips) * key.fee / 1_000_000;
    if (perDirection > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) {
      perDirection = ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
    }
    return uint24((perDirection << 12) | perDirection);
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

/// @notice A ruleset whose getProtocolFee burns the gas of the call with INVALID.
contract MockOutOfGasRuleset {
  fallback() external {
    assembly {
      invalid()
    }
  }
}

/// @notice A ruleset whose getProtocolFee returns fewer than 32 bytes.
contract MockShortReturnRuleset {
  fallback() external {
    assembly {
      return(0x00, 0x10)
    }
  }
}

/// @notice A hook whose every call reverts. ERC165Checker treats a reverting supportsInterface
/// as "not supported", so computeFee does not revert on the opt-in check.
contract MockRevertingHook {
  error MockReverted();

  fallback() external {
    revert MockReverted();
  }
}

/// @notice A hook that returns one raw word for every call. ERC165Checker treats a zero word as
/// "not supported". A nonzero word for every id, including the invalid id 0xffffffff, also fails
/// the ERC165 check, so the hook has not opted in.
contract MockGarbageHook {
  uint256 internal immutable WORD;

  constructor(uint256 word) {
    WORD = word;
  }

  fallback() external {
    uint256 word = WORD;
    assembly {
      mstore(0x00, word)
      return(0x00, 0x20)
    }
  }
}
