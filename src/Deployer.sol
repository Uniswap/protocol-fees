// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {V3FeeController} from "./feeControllers/V3FeeController.sol";
import {IAssetSink} from "./interfaces/IAssetSink.sol";
import {AssetSink} from "./AssetSink.sol";
import {Firepit} from "./releasers/Firepit.sol";
import {UNIMinter} from "./UNIMinter.sol";
import {IReleaser} from "./interfaces/IReleaser.sol";
import {IV3FeeController} from "./interfaces/IV3FeeController.sol";
import {IUNIMinter} from "./interfaces/IUNIMinter.sol";
import {IOwned} from "./interfaces/base/IOwned.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract Deployer {
  IAssetSink public immutable ASSET_SINK;
  IReleaser public immutable RELEASER;
  IV3FeeController public immutable FEE_CONTROLLER;
  IUNIMinter public immutable UNI_MINTER;

  address public constant RESOURCE = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
  uint256 public constant THRESHOLD = 10_000e18;
  IUniswapV3Factory public constant V3_FACTORY =
    IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

  // Using the real merkle root from the generated merkle tree in ./merkle-generator
  bytes32 constant INITIAL_MERKLE_ROOT =
    bytes32(0x472c8960ea78de635eb7e32c5085f9fb963e626b5a68c939bfad24e022383b3a);

  uint8 constant DEFAULT_FEE_100 = 4 << 4 | 4; // default fee for 0.01% tier
  uint8 constant DEFAULT_FEE_500 = 6 << 4 | 6; // default fee for 0.05% tier
  uint8 constant DEFAULT_FEE_3000 = 8 << 4 | 8; // default fee for 0.3% tier
  uint8 constant DEFAULT_FEE_10000 = 10 << 4 | 10; // default fee for 1% tier

  bytes32 constant SALT_ASSET_SINK = bytes32(uint256(1));
  bytes32 constant SALT_RELEASER = bytes32(uint256(2));
  bytes32 constant SALT_FEE_CONTROLLER = bytes32(uint256(3));

  //// ASSET SINK:
  /// 1. Deploy the AssetSink
  /// 3. Set the releaser on the asset sink.
  /// 4. Update the owner on the asset sink.

  /// RELEASER:
  /// 2. Deploy the Releaser.
  /// 5. Update the thresholdSetter on the releaser to the owner.
  /// 6. Update the owner on the releaser.

  /// FEE_CONTROLLER:
  /// 7. Deploy the FeeController.
  /// 8. Set this contract as the feeSetter
  /// 9. Set initial merkle root
  /// 10. Set default fees
  /// 11. Update the feeSetter to the owner.
  /// 12. Store fee tiers.
  /// 13. Update the owner on the fee controller.

  /// UNIMinter
  /// 14. Deploy the UNIMinter
  ///   - To enable the UNIMinter, the owner must call `setMinter` on the UNI contract
  constructor() {
    address owner = V3_FACTORY.owner();
    /// 1. Deploy the AssetSink.
    ASSET_SINK = new AssetSink{salt: SALT_ASSET_SINK}();
    /// 2. Deploy the Releaser.
    RELEASER = new Firepit{salt: SALT_RELEASER}(RESOURCE, THRESHOLD, address(ASSET_SINK));
    /// 3. Set the releaser on the asset sink.
    ASSET_SINK.setReleaser(address(RELEASER));
    /// 4. Update the owner on the asset sink.
    IOwned(address(ASSET_SINK)).transferOwnership(owner);

    /// 5. Update the thresholdSetter on the releaser to the owner.
    RELEASER.setThresholdSetter(owner);
    /// 6. Update the owner on the releaser.
    IOwned(address(RELEASER)).transferOwnership(owner);

    /// 7. Deploy the FeeController.
    FEE_CONTROLLER =
      new V3FeeController{salt: SALT_FEE_CONTROLLER}(address(V3_FACTORY), address(ASSET_SINK));

    /// 8. Set this contract as the feeSetter
    FEE_CONTROLLER.setFeeSetter(address(this));

    /// 9. Set initial merkle root
    FEE_CONTROLLER.setMerkleRoot(INITIAL_MERKLE_ROOT);

    /// 10. Set default fees
    FEE_CONTROLLER.setDefaultFeeByFeeTier(100, DEFAULT_FEE_100);
    FEE_CONTROLLER.setDefaultFeeByFeeTier(500, DEFAULT_FEE_500);
    FEE_CONTROLLER.setDefaultFeeByFeeTier(3000, DEFAULT_FEE_3000);
    FEE_CONTROLLER.setDefaultFeeByFeeTier(10_000, DEFAULT_FEE_10000);

    /// 11. Update the feeSetter to the owner.
    FEE_CONTROLLER.setFeeSetter(owner);

    /// 12. Store fee tiers.
    FEE_CONTROLLER.storeFeeTier(100);
    FEE_CONTROLLER.storeFeeTier(500);
    FEE_CONTROLLER.storeFeeTier(3000);
    FEE_CONTROLLER.storeFeeTier(10_000);

    /// 13. Update the owner on the fee controller.
    IOwned(address(FEE_CONTROLLER)).transferOwnership(owner);

    /// 14. Deploy the UNIMinter
    UNI_MINTER = new UNIMinter(owner);
  }
}
