// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniswapV3PoolOwnerActions} from "src/interfaces/IUniswapV3PoolOwnerActions.sol";
import {IUniswapV3FactoryOwnerActions} from "src/interfaces/IUniswapV3FactoryOwnerActions.sol";

/// @title IUniswapFeeManager
/// @notice An interface to manage protocol fee acquisition for push-value and pull-token Uniswap
/// protocol fees
interface IUniswapFeeManager {
  /// @notice Emitted when a user pays the payout and claims the fees from a given v3 pool.
  /// @param pool The v3 pool from which protocol fees were claimed.
  /// @param caller The address which executes the call to claim the fees.
  /// @param recipient The address to which the claimed pool fees are sent.
  /// @param amount0 The raw amount of token0 fees claimed from the pool.
  /// @param amount1 The raw amount token1 fees claimed from the pool. optionally zero for Uniswap
  /// v4
  event FeesClaimed(
    bytes32 indexed pool,
    address indexed caller,
    address indexed recipient,
    uint256 amount0,
    uint256 amount1
  );

  /// @notice Emitted when the existing admin designates a new address as the admin.
  event AdminSet(address indexed oldAdmin, address indexed newAdmin);

  /// @notice Emitted when the admin updates the global protocol fee.
  event GlobalProtocolFeeSet(
    uint8 indexed oldGlobalProtocolFee, uint8 indexed newGlobalProtocolFee
  );

  /// @notice Emitted when the admin enacts the fee protocol override for a pool.
  event FeeProtocolOverrideEnacted(
    bytes32 indexed pool, uint8 indexed feeProtocol0, uint8 indexed feeProtocol1
  );

  /// @notice Emitted when the admin removes the fee protocol override for a pool.
  event FeeProtocolOverrideRemoved(IUniswapV3PoolOwnerActions indexed pool);

  /// @notice The data structure accepted as an argument to `claimFees`.
  struct ClaimInputData {
    /// @notice The Uniswap v3 pool from which protocol fees are collected.
    IUniswapV3PoolOwnerActions pool;
    /// @notice The amount of the pool's token0 to forward to the
    /// pool's `collectProtocol` function.
    uint128 amount0Requested;
    /// @notice The amount of the pool's token1 to forward to the
    /// pool's `collectProtocol` function.
    uint128 amount1Requested;
  }

  /// @notice The data structure returned by `claimFees`.
  struct ClaimOutputData {
    /// @notice The Uniswap v3 pool from which protocol fees were collected.
    IUniswapV3PoolOwnerActions pool;
    /// @notice The amount of the pool's token0 collected.
    uint128 amount0;
    /// @notice The amount of the pool's token1 collected.
    uint128 amount1;
  }

  /// @notice The data structure accepted as an argument to `setFeeProtocolOverride`.
  struct FeeProtocolOverride {
    /// @notice The Uniswap v3 pool on which the fee protocol is being set.
    IUniswapV3PoolOwnerActions pool;
    /// @notice The fee protocol for token0.
    uint8 feeProtocol0;
    /// @notice The fee protocol for token1.
    uint8 feeProtocol1;
  }

  /// @notice Thrown when an unauthorized account calls a privileged function.
  error Unauthorized();

  /// @notice Thrown if the proposed admin is the zero address.
  error InvalidAddress();

  /// @notice Thrown if the proposed global protocol fee is an unsupported value.
  /// Supported values are limited to 0 and 4-10 inclusive.
  error InvalidGlobalProtocolFee();

  /// @notice Thrown when the fees collected from a pool are less than the caller expects.
  error InsufficientFeesCollected();

  /// @notice Thrown when the caller does not provide any claim information.
  error NoClaimInputProvided();

  /// @notice Thrown when attempting to set the fee protocol for a pool that has a fee protocol
  /// override.
  error FeeProtocolOverrideError(bytes32 pool);

  /// @notice Returns the default protocol fee that can be applied to pools created by `FACTORY`.
  ///
  /// It is the denominator of the fraction of the swapper fees that are collected by the Uni v3
  /// protocol. It is either 0 (i.e. no fee) or 4-10, representing 1/4 to 1/10th (respectively) of
  /// the swapper fee.
  ///
  /// https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/UniswapV3Pool.sol#L838-L841
  ///
  /// For example, if globalProtocolFee is 5 and the swapper fee is 0.3% then the protocol claims
  /// 0.3% / 5 = 0.06% of the transaction.
  function globalProtocolFee() external view returns (uint8);

  /// @notice Returns the contract that receives the payout when pool fees are claimed.
  function FEE_RECEIVER() external view returns (address);

  /// @notice Returns the address that can call privileged methods, including passthrough owner
  /// functions to the factory itself.
  function admin() external view returns (address);

  /// @notice Returns whether the fee protocol is overridden for a given pool.
  function isFeeProtocolOverridden(bytes32 pool) external view returns (bool);

  /// @notice Pass the admin role to a new address. Must be called by the existing admin.
  /// @param _newAdmin The address that will be the admin after this call completes.
  function setAdmin(address _newAdmin) external;

  /// @notice Enact the fee protocol override for a given pool or pools. Must be called by admin.
  /// @param _feeProtocolOverrides The pools and fee protocol args to set.
  /// @dev Emits `FeeProtocolOverrideEnacted` event for each pool.
  function enactFeeProtocolOverride(bytes32[] calldata _feeProtocolOverrides) external;

  /// @notice Remove the fee protocol override for a given pool or pools. Must be called by admin.
  /// @param _pools The pools to remove the fee protocol override for.
  /// @dev Emits `FeeProtocolOverrideRemoved` event for each pool.
  function removeFeeProtocolOverride(bytes32[] calldata _pools) external;

  /// @notice Set the global protocol fee for all pools created by the factory.
  /// Must be called by the admin.
  /// @param _globalProtocolFee The new global protocol fee to be set.
  /// @dev Emits `GlobalProtocolFeeSet` event.
  /// @dev If the global protocol fee is reduced, MEV searchers and UNI token holders may not be
  /// incentivized to call `setFeeProtocol`, as they'd lose out on fees at the former fee rate.
  /// Governance might consider some plan for incentivizing or subsidizing calls to
  /// `setFeeProtocol` in this case.
  function setGlobalProtocolFee(uint8 _globalProtocolFee) external;

  /// @notice Passthrough method that enables a fee amount on the factory. Must be called by the
  /// admin.
  /// @param _pool the identifier for a Uniswap pool
  /// @param _fee The fee amount to enable.
  function enableFeeAmount(bytes32 _pool, uint24 _fee) external;

  /// @notice Passthrough method that sets the protocol fee on a v3 pool to the
  /// `globalProtocolFee` defined in this contract. May be called by any address.
  /// @param _pool The Uniswap v3 pool on which the protocol fee is being set.
  /// @dev If the pool has a fee protocol override, this call will revert.
  /// @dev See docs on IUniswapV3PoolOwnerActions for more information on forwarded params.
  function setFeeProtocol(bytes32 _pool) external;

  /// @notice Passthrough method that sets the protocol fee on multiple v3 pools
  /// to the `globalProtocolFee` defined in this contract. May be called by any
  /// address.
  /// @param _pools The Uniswap v3 pools on which the protocol fee is being set.
  /// @dev If any pool has a fee protocol override, this call will revert.
  function setFeeProtocol(bytes32[] calldata _pools) external;

  function claimFees(
    bytes32[] calldata pools,
    address[] calldata tokens,
    uint256[] calldata amounts
  ) external;

  function claimFees(bytes32 pool, address token, uint256 amount) external;
}
