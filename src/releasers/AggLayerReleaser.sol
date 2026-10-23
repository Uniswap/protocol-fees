// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {IAggLayerBridge} from "../interfaces/external/IAggLayerBridge.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ExchangeReleaser} from "./ExchangeReleaser.sol";

/// @title AggLayerReleaser
/// @notice A releaser that implements a two-stage burn for resource tokens bridged to an AggLayer
/// chain (e.g. X Layer) through Polygon's AggLayer unified bridge
/// @dev Two-stage burn from an AggLayer chain to the underlying resource on Ethereum
/// **Stage 1: L2 Collection and Bridge Initiation**
/// - User calls `release()` providing resource tokens as payment
/// - ExchangeReleaser transfers resource tokens from user to this smart contract
/// - TokenJar releases accumulated fee assets to the specified recipient
/// - _afterRelease() calls `bridgeAsset` on the unified bridge with destination network 0
///   (Ethereum) and destination address 0xdead
/// **Stage 2: Ethereum Finalization**
/// - The unified bridge burns the wrapped resource held by this contract and appends a leaf to
///   this chain's local exit tree
/// - The chain's aggregator settles the new local exit root on Ethereum through the rollup manager
/// - Anyone submits `claimAsset` on the Ethereum bridge with the exit proof (permissionless, and
///   the bridge service normally auto-claims); the Ethereum bridge transfers the escrowed
///   resource to 0xdead
/// @dev Unlike OP Stack and Arbitrum withdrawals there is no challenge period, but the claim on
/// Ethereum is a separate transaction that someone must submit once the exit root has settled.
/// @dev X Layer nuances: the chain's gas token is OKB rather than Ether. `bridgeAsset` is payable
/// but rejects nonzero value for ERC20s, so no native token is required and this contract does
/// not accept any. The X Layer bridge mints its own wrapped UNI (`TokenWrapped`) for Ethereum UNI
/// and burns it directly from the caller rather than pulling it through an allowance. X Layer also
/// carries OP Stack predeploys and an `OptimismMintableERC20` UNI; that token is a different asset
/// and the constructor rejects it, since the unified bridge does not recognize it.
/// @custom:security-contact security@uniswap.org
contract AggLayerReleaser is ExchangeReleaser {
  using SafeTransferLib for ERC20;

  error ZeroAddress();

  /// @dev Thrown when the bridge does not recognize the resource as its wrapped representation of
  /// `L1_RESOURCE` from Ethereum. Bridging any other token would escrow it on this chain and mint
  /// a wrapped token on Ethereum instead of burning the resource.
  error ResourceNotWrappedL1Resource();

  /// @dev AggLayer network id of Ethereum mainnet, the settlement layer of every AggLayer chain
  uint32 public constant AGGLAYER_ETHEREUM_NETWORK_ID = 0;

  /// @dev Final recipient of the bridged resource on Ethereum (burn address)
  /// @dev Note: This is different from RESOURCE_RECIPIENT which is address(this) on L2
  address internal constant L1_RESOURCE_RECIPIENT = address(0xdead);

  /// @dev The AggLayer unified bridge on this chain
  /// @dev Deployed at 0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe on X Layer and most CDK chains,
  /// but it is not a predeploy, so it is a constructor parameter
  IAggLayerBridge public immutable BRIDGE;

  /// @dev The resource token address on Ethereum, the origin token of the wrapped resource
  /// @dev Used to check at construction that the bridge maps `RESOURCE` back to it
  address public immutable L1_RESOURCE;

  /// @notice Creates a new AggLayerReleaser instance
  /// @param _bridge The AggLayer unified bridge on this chain
  /// @param _resource The address of the resource token on this chain (bridge wrapped token)
  /// @param _l1Resource The address of the resource token on Ethereum (origin token)
  /// @param _threshold The minimum amount of resource tokens required for exchange
  /// @param _tokenJar The address of the TokenJar contract holding accumulated fee assets
  /// @dev Sets RESOURCE_RECIPIENT to address(this) to enable the two-stage burn:
  ///      Stage 1: Collect tokens here (L2) -> Stage 2: Bridge and burn on Ethereum
  /// @dev Reverts unless the bridge reports `_resource` as the wrapped token of `_l1Resource`
  /// from Ethereum, so a native or otherwise-bridged token cannot be configured by mistake
  constructor(
    address _bridge,
    address _resource,
    address _l1Resource,
    uint256 _threshold,
    address _tokenJar
  ) ExchangeReleaser(_resource, _threshold, _tokenJar, address(this)) {
    require(_bridge != address(0), ZeroAddress());
    require(_l1Resource != address(0), ZeroAddress());
    BRIDGE = IAggLayerBridge(_bridge);
    L1_RESOURCE = _l1Resource;

    (uint32 originNetwork, address originTokenAddress) = BRIDGE.wrappedTokenToTokenInfo(_resource);
    require(
      originNetwork == AGGLAYER_ETHEREUM_NETWORK_ID && originTokenAddress == _l1Resource,
      ResourceNotWrappedL1Resource()
    );
  }

  /// @notice Hook called after assets are released - initiates stage 2 withdrawal to Ethereum
  /// @dev The allowance is only consumed if the chain maps the resource to a token the bridge
  /// cannot mint and burn itself (a "not mintable" sovereign token). For a bridge-minted wrapped
  /// token, as on X Layer, the bridge burns directly and the allowance is left in place. That is
  /// harmless: the bridge only ever transfers from `msg.sender`, so it can only be spent during
  /// this contract's own `bridgeAsset` calls, and it is overwritten rather than accumulated.
  function _afterRelease(Currency[] calldata, address) internal override {
    // Stage 2: Initiate bridge withdrawal to the Ethereum burn address
    // The bridge will:
    // 1. Burn the wrapped resource held by this contract
    // 2. Append a leaf to the local exit tree and push the new root to the global exit root
    // 3. After settlement on Ethereum, `claimAsset` releases the escrowed resource to 0xdead
    RESOURCE.safeApprove(address(BRIDGE), threshold);
    BRIDGE.bridgeAsset({
      destinationNetwork: AGGLAYER_ETHEREUM_NETWORK_ID,
      destinationAddress: L1_RESOURCE_RECIPIENT,
      amount: threshold,
      token: address(RESOURCE),
      forceUpdateGlobalExitRoot: true,
      permitData: bytes("")
    });
  }
}
