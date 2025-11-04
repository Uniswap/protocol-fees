// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {V3FeeAdapter} from "./feeAdapters/V3FeeAdapter.sol";
import {IAssetSink} from "./interfaces/IAssetSink.sol";
import {AssetSink} from "./AssetSink.sol";
import {Firepit} from "./releasers/Firepit.sol";
import {UNIMinter} from "./UNIMinter.sol";
import {IReleaser} from "./interfaces/IReleaser.sol";
import {IV3FeeAdapter} from "./interfaces/IV3FeeAdapter.sol";
import {IUNIMinter} from "./interfaces/IUNIMinter.sol";
import {IOwned} from "./interfaces/base/IOwned.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract Deployer {
  IAssetSink public immutable ASSET_SINK;
  IReleaser public immutable RELEASER;
  IV3FeeAdapter public immutable FEE_ADAPTER;
  IUNIMinter public immutable UNI_MINTER;

  address public constant RESOURCE = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
  uint256 public constant THRESHOLD = 69_420;
  IUniswapV3Factory public constant V3_FACTORY =
    IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

  bytes32 constant SALT_ASSET_SINK = 0;
  bytes32 constant SALT_RELEASER = 0;
  bytes32 constant SALT_FEE_ADAPTER = 0;

  //// ASSET SINK:
  /// 1. Deploy the AssetSink
  /// 3. Set the releaser on the asset sink.
  /// 4. Update the owner on the asset sink.

  /// RELEASER:
  /// 2. Deploy the Releaser.
  /// 5. Update the thresholdSetter on the releaser to the owner.
  /// 6. Update the owner on the releaser.

  /// FEE_ADAPTER:
  /// 7. Deploy the FeeAdapter.
  /// 8. Update the feeSetter to the owner.
  /// 9. Store fee tiers.
  /// 10. Update the owner on the fee adapter.

  /// UNIMinter
  /// 11. Deploy the UNIMinter
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

    /// 7. Deploy the FeeAdapter.
    FEE_ADAPTER =
      new V3FeeAdapter{salt: SALT_FEE_ADAPTER}(address(V3_FACTORY), address(ASSET_SINK));

    /// 8. Update the feeSetter to the owner.
    FEE_ADAPTER.setFeeSetter(owner);

    /// 9. Store fee tiers.
    FEE_ADAPTER.storeFeeTier(100);
    FEE_ADAPTER.storeFeeTier(500);
    FEE_ADAPTER.storeFeeTier(3000);
    FEE_ADAPTER.storeFeeTier(10_000);

    /// 10. Update the owner on the fee adapter.
    IOwned(address(FEE_ADAPTER)).transferOwnership(owner);

    /// 11. Deploy the UNIMinter
    UNI_MINTER = new UNIMinter(owner);
  }
}
