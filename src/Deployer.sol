// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {V3FeeAdapter} from "./feeAdapters/V3FeeAdapter.sol";
import {ITokenJar} from "./interfaces/ITokenJar.sol";
import {TokenJar} from "./TokenJar.sol";
import {Firepit} from "./releasers/Firepit.sol";
import {IUNIVesting} from "./interfaces/IUNIVesting.sol";
import {UNIVesting} from "./UNIVesting.sol";
import {IReleaser} from "./interfaces/IReleaser.sol";
import {IV3FeeAdapter} from "./interfaces/IV3FeeAdapter.sol";
import {IOwned} from "./interfaces/base/IOwned.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract Deployer {
  ITokenJar public immutable TOKEN_JAR;
  IReleaser public immutable RELEASER;
  IV3FeeAdapter public immutable V3_FEE_ADAPTER;
  IUNIVesting public immutable UNI_VESTING;

  address public constant RESOURCE = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
  uint256 public constant THRESHOLD = 10_000e18;
  IUniswapV3Factory public constant V3_FACTORY =
    IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
  // TODO: set with the real UNI recipient when ready
  address public constant LABS_UNI_RECIPIENT = 0x0000000000000000000000000000000000000001;

  // Using the real merkle root from the generated merkle tree in ./merkle-generator
  // TODO: Regenerate the merkle tree
  bytes32 constant INITIAL_MERKLE_ROOT =
    bytes32(0x472c8960ea78de635eb7e32c5085f9fb963e626b5a68c939bfad24e022383b3a);

  uint8 constant DEFAULT_FEE_100 = 4 << 4 | 4; // default fee for 0.01% tier
  uint8 constant DEFAULT_FEE_500 = 4 << 4 | 4; // default fee for 0.05% tier
  uint8 constant DEFAULT_FEE_3000 = 6 << 4 | 6; // default fee for 0.3% tier
  uint8 constant DEFAULT_FEE_10000 = 6 << 4 | 6; // default fee for 1% tier

  bytes32 constant SALT_TOKEN_JAR = bytes32(uint256(1));
  bytes32 constant SALT_RELEASER = bytes32(uint256(2));
  bytes32 constant SALT_V3_FEE_ADAPTER = bytes32(uint256(3));
  bytes32 constant SALT_UNI_VESTING = bytes32(uint256(4));

  //// TOKEN JAR:
  /// 1. Deploy the TokenJar
  /// 3. Set the releaser on the token jar.
  /// 4. Update the owner on the token jar.

  /// RELEASER:
  /// 2. Deploy the Releaser.
  /// 5. Update the thresholdSetter on the releaser to the owner.
  /// 6. Update the owner on the releaser.

  /// FEE_ADAPTER
  /// 7. Deploy the FeeAdapter.
  /// 8. Update the feeSetter to the owner.
  /// 9. Store fee tiers.
  /// 10. Update the owner on the fee adapter.
  /// 8. Set this contract as the feeSetter
  /// 9. Set initial merkle root
  /// 10. Set default fees
  /// 11. Update the feeSetter to the owner.
  /// 12. Store fee tiers.
  /// 13. Update the owner on the fee adapter.

  /// UNI_VESTING
  /// 14. Deploy the UNIVesting contract.
  /// 15. Update the owner on the UNIVesting contract.
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
    V3_FEE_ADAPTER =
      new V3FeeAdapter{salt: SALT_V3_FEE_ADAPTER}(address(V3_FACTORY), address(TOKEN_JAR));

    /// 8. Set this contract as the feeSetter
    V3_FEE_ADAPTER.setFeeSetter(address(this));

    /// 9. Set initial merkle root
    V3_FEE_ADAPTER.setMerkleRoot(INITIAL_MERKLE_ROOT);

    /// 10. Set default fees
    V3_FEE_ADAPTER.setDefaultFeeByFeeTier(100, DEFAULT_FEE_100);
    V3_FEE_ADAPTER.setDefaultFeeByFeeTier(500, DEFAULT_FEE_500);
    V3_FEE_ADAPTER.setDefaultFeeByFeeTier(3000, DEFAULT_FEE_3000);
    V3_FEE_ADAPTER.setDefaultFeeByFeeTier(10_000, DEFAULT_FEE_10000);

    /// 11. Update the feeSetter to the owner.
    V3_FEE_ADAPTER.setFeeSetter(owner);

    /// 12. Store fee tiers.
    V3_FEE_ADAPTER.storeFeeTier(100);
    V3_FEE_ADAPTER.storeFeeTier(500);
    V3_FEE_ADAPTER.storeFeeTier(3000);
    V3_FEE_ADAPTER.storeFeeTier(10_000);

    /// 13. Update the owner on the fee adapter.
    IOwned(address(V3_FEE_ADAPTER)).transferOwnership(owner);

    /// 14. Deploy the UNIVesting contract.
    UNI_VESTING =
      IUNIVesting(new UNIVesting{salt: SALT_UNI_VESTING}(address(RESOURCE), LABS_UNI_RECIPIENT));

    /// 15. Update the owner on the UNIVesting contract.
    IOwned(address(UNI_VESTING)).transferOwnership(owner);
  }
}
