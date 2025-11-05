// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Predeploys} from "@eth-optimism-bedrock/src/libraries/Predeploys.sol";
import {IL2StandardBridge} from "../interfaces/external/IL2StandardBridge.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ResourceManager} from "../base/ResourceManager.sol";
import {Nonce} from "../base/Nonce.sol";
import {IAssetSink} from "../interfaces/IAssetSink.sol";
import {IReleaser} from "../interfaces/IReleaser.sol";

/// @title OptimismBridgedResourceFirepit
/// @notice A releaser that withdraws a bridged resource to the burn address on L1 via OP standard
/// bridge
/// @custom:security-contact security@uniswap.org
abstract contract OptimismBridgedResourceFirepit is IReleaser, ResourceManager, Nonce {
  using SafeTransferLib for ERC20;

  /// @inheritdoc IReleaser
  IAssetSink public immutable ASSET_SINK;
  uint32 internal constant WITHDRAWAL_MIN_GAS = 35_000;

  /// @notice Creates a new ExchangeReleaser instance
  /// @param _resource The address of the resource token that must be transferred
  /// @param _assetSink The address of the AssetSink contract holding the assets
  constructor(address _resource, uint256 _threshold, address _assetSink)
    ResourceManager(_resource, _threshold, msg.sender, address(0xdead))
  {
    // assert resource is an OptimismMintableERC20
    ASSET_SINK = IAssetSink(payable(_assetSink));
  }

  /// @inheritdoc IReleaser
  function release(uint256 _nonce, Currency[] calldata assets, address recipient) external virtual {
    _release(_nonce, assets, recipient);
  }

  /// @notice Internal function to handle the nonce check, withdraw the RESOURCE, then
  /// handle the release of assets on the AssetSink.
  function _release(uint256 _nonce, Currency[] calldata assets, address recipient)
    internal
    handleNonce(_nonce)
  {
    // Transfer resource from caller into this contract
    RESOURCE.safeTransferFrom(msg.sender, address(this), threshold);
    // Withdraw the resource back to L1 burn address
    IL2StandardBridge(Predeploys.L2_STANDARD_BRIDGE)
      .withdrawTo(address(RESOURCE), RESOURCE_RECIPIENT, threshold, WITHDRAWAL_MIN_GAS, bytes(""));
    ASSET_SINK.release(assets, recipient);
  }
}
