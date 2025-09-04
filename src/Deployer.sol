// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {V3FeeController} from "./feeControllers/V3FeeController.sol";
import {AssetSink} from "./AssetSink.sol";
import {Firepit} from "./releasers/Firepit.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract Deployer {
  address RESOURCE;
  uint256 THRESHOLD;
  IUniswapV3Factory V3_FACTORY;

  bytes32 ASSET_SINK_SALT = 0;
  bytes32 RELEASER_SALT = 0;
  bytes32 FEE_CONTROLLER_SALT = 0;

  //// ASSET SINK:
  /// 1. Deploy the AssetSink
  /// 3. Set the releaser on the asset sink.
  /// 4. Update the owner on the asset sink.

  /// RELEASER:
  /// 2. Deploy the Releaser.
  /// 7. Update the owner on the releaser.
  /// 6. Update the thresholdSetter on the releaser to the owner.
  /// 5. Update the threshold on the releaser.

  /// FEE_CONTROLLER:
  /// 8.Deploy the FeeController.
  /// 9. Update the feeSetter to the owner.
  /// 10. Update the owner on the fee controller.
  constructor() {
    address owner = V3_FACTORY.owner();
    /// 1. Deploy the AssetSink.
    AssetSink assetSink = new AssetSink{salt: ASSET_SINK_SALT}();
    /// 2. Deploy the Releaser.
    Firepit releaser = new Firepit{salt: RELEASER_SALT}(RESOURCE, address(assetSink));
    /// 3. Set the releaser on the asset sink.
    assetSink.setReleaser(address(releaser));
    /// 4. Update the owner on the asset sink.
    assetSink.transferOwnership(owner);

    /// 5. Update the threshold on the releaser.
    releaser.setThreshold(THRESHOLD);
    /// 6. Update the thresholdSetter on the releaser to the owner.
    releaser.setThresholdSetter(owner);
    /// 7. Update the owner on the releaser.
    releaser.transferOwnership(owner);

    /// 8. Deploy the FeeController.
    V3FeeController feeController =
      new V3FeeController{salt: FEE_CONTROLLER_SALT}(address(V3_FACTORY), address(assetSink));

    /// 9. Update the feeSetter to the owner.

    /// 10. Update the owner on the fee controller.
    feeController.transferOwnership(owner);
  }
}
