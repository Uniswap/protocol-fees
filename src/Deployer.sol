// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {V3FeeController} from "./feeControllers/V3FeeController.sol";
import {AssetSink, IAssetSink} from "./AssetSink.sol";
import {Firepit} from "./releasers/Firepit.sol";
import {IReleaser} from "./interfaces/IReleaser.sol";
import {IV3FeeController} from "./interfaces/IV3FeeController.sol";
import {IOwned} from "./interfaces/base/IOwned.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract Deployer {
  IAssetSink public immutable ASSET_SINK;
  IReleaser public immutable RELEASER;
  IV3FeeController public immutable FEE_CONTROLLER;

  address public constant RESOURCE = 0x1000000000000000000000000000000000000000;
  uint256 public constant THRESHOLD = 69_420;
  IUniswapV3Factory public constant V3_FACTORY =
    IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

  bytes32 constant SALT_ASSET_SINK = 0;
  bytes32 constant SALT_RELEASER = 0;
  bytes32 constant SALT_FEE_CONTROLLER = 0;

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
  /// 8. Update the feeSetter to the owner.
  /// 9. Update the owner on the fee controller.
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

    /// 8. Update the feeSetter to the owner.
    FEE_CONTROLLER.setFeeSetter(owner);

    /// 9. Update the owner on the fee controller.
    IOwned(address(FEE_CONTROLLER)).transferOwnership(owner);
  }
}
