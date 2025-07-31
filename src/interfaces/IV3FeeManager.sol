// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniswapV3PoolOwnerActions} from "src/interfaces/IUniswapV3PoolOwnerActions.sol";
import {IUniswapV3FactoryOwnerActions} from "src/interfaces/IUniswapV3FactoryOwnerActions.sol";

/// @title IV3FeeManager
/// @author [ScopeLift](https://scopelift.co)
/// @notice A contract to manage protocol fee acquisition for Uniswap V3.
///
/// It is expected that this contract will be the owner of the `UniswapV3Factory` and as such have
/// access to privileged functions on that factory.
///
/// This contract has an admin. The admin retains exclusive right to:
///   * enable fee amounts on the v3 factory; this behavior exercises owner privileges
///   * set a global protocol fee level; this fee (collected and retained for the Uniswap protocol)
///     can be enabled on any pool created by the v3 factory via the public `setFeeProtocol`
///     function, which also exercises owner privileges
///   * set the fee receiver address; this is the address which receives transfers of
///     protocol fees for a claimed pool.
///   * transfer admin privileges to another address
///
/// One privileged v3 factory function that is _not_ reserved exclusively for the admin is the
/// ability to collect protocol fees from a pool. This method is instead exposed publicly by this
/// contract's `claimFees` method. That method collects fees from the protocol and forwards them
/// to the fee receiver.
///
/// Another privileged v3 factory function that is publicly exposed is the `setFeeProtocol`
/// function. This function sets the protocol fees on a given v3 pool to the `globalProtocolFee`
/// defined in this contract.
interface IV3FeeManager {
  /// @notice Emitted when a user pays the payout and claims the fees from a given v3 pool.
  /// @param pool The v3 pool from which protocol fees were claimed.
  /// @param caller The address which executes the call to claim the fees.
  /// @param recipient The address to which the claimed pool fees are sent.
  /// @param amount0 The raw amount of token0 fees claimed from the pool.
  /// @param amount1 The raw amount token1 fees claimed from the pool.
  event FeesClaimed(
    address indexed pool,
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
    IUniswapV3PoolOwnerActions indexed pool, uint8 indexed feeProtocol0, uint8 indexed feeProtocol1
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
  error V3FeeManager__Unauthorized();

  /// @notice Thrown if the proposed admin is the zero address.
  error V3FeeManager__InvalidAddress();

  /// @notice Thrown if the proposed global protocol fee is an unsupported value.
  /// Supported values are limited to 0 and 4-10 inclusive.
  error V3FeeManager__InvalidGlobalProtocolFee();

  /// @notice Thrown when the fees collected from a pool are less than the caller expects.
  error V3FeeManager__InsufficientFeesCollected();

  /// @notice Thrown when the caller does not provide any claim information.
  error V3FeeManager__NoClaimInputProvided();

  /// @notice Thrown when attempting to set the fee protocol for a pool that has a fee protocol
  /// override.
  error V3FeeManager__FeeProtocolOverride(IUniswapV3PoolOwnerActions pool);

  /// @notice Returns the instance of the Uniswap v3 factory contract which this contract will own.
  function FACTORY() external view returns (IUniswapV3FactoryOwnerActions);

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
  function isFeeProtocolOverridden(IUniswapV3PoolOwnerActions pool) external view returns (bool);

  /// @notice Pass the admin role to a new address. Must be called by the existing admin.
  /// @param _newAdmin The address that will be the admin after this call completes.
  function setAdmin(address _newAdmin) external;

  /// @notice Enact the fee protocol override for a given pool or pools. Must be called by admin.
  /// @param _feeProtocolOverrides The pools and fee protocol args to set.
  /// @dev Emits `FeeProtocolOverrideEnacted` event for each pool.
  function enactFeeProtocolOverride(FeeProtocolOverride[] calldata _feeProtocolOverrides) external;

  /// @notice Remove the fee protocol override for a given pool or pools. Must be called by admin.
  /// @param _pools The pools to remove the fee protocol override for.
  /// @dev Emits `FeeProtocolOverrideRemoved` event for each pool.
  function removeFeeProtocolOverride(IUniswapV3PoolOwnerActions[] calldata _pools) external;

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
  /// @param _fee The fee param to forward to the factory.
  /// @param _tickSpacing The tick spacing param to forward to the factory.
  /// @dev See docs on IUniswapV3FactoryOwnerActions for more information on forwarded params.
  function enableFeeAmount(uint24 _fee, int24 _tickSpacing) external;

  /// @notice Passthrough method that sets the protocol fee on a v3 pool to the
  /// `globalProtocolFee` defined in this contract. May be called by any address.
  /// @param _pool The Uniswap v3 pool on which the protocol fee is being set.
  /// @dev If the pool has a fee protocol override, this call will revert.
  /// @dev See docs on IUniswapV3PoolOwnerActions for more information on forwarded params.
  function setFeeProtocol(IUniswapV3PoolOwnerActions _pool) external;

  /// @notice Passthrough method that sets the protocol fee on multiple v3 pools
  /// to the `globalProtocolFee` defined in this contract. May be called by any
  /// address.
  /// @param _pools The Uniswap v3 pools on which the protocol fee is being set.
  /// @dev If any pool has a fee protocol override, this call will revert.
  function setFeeProtocol(IUniswapV3PoolOwnerActions[] calldata _pools) external;

  /// @notice Public method that allows any caller to claim the protocol fees accrued by multiple
  /// Uniswap v3 pool contract. The protocol fees collected are sent to the fee receiver. The fee
  /// receiver will be the `ERC20FeeCollector` which has a payout race to convert fees to a payout
  /// token. `claimFees` should be called by MEV searchers in the payout race flow.
  ///
  /// A quick example can help illustrate why an external party, such as an MEV searcher, would be
  /// incentivized to call this method. Imagine, purely for the sake of example, that protocol fees
  /// have been activated for the USDC/USDT stablecoin v3 pool. Imagine also the payout token and
  /// payout amount on the `ERC20FeeCollector` are WETH and 10e18 respectively. Finally, assume the
  /// spot USD price of ETH is $2,500, and both stablecoins are trading at their $1 peg. As regular
  /// users trade against the USDC/USDT pool, protocol fees amass in the pool contract in both
  /// stablecoins. Once the fees in the pool total more than 25,000 in stablecoins, it becomes
  /// profitable for an external party to arbitrage the fees by calling this method and then
  /// `claimFees` on the `ERC20FeeCollector`, paying 10 WETH (worth $25K) and getting more than
  /// $25K worth of stablecoins. (This ignores other details, which real searchers would take into
  /// consideration, such as the gas/builder fee they would pay to call the method).
  /// Effectively, as each pool accrues fees, it eventually becomes possible to "buy" the pool fees
  /// for less than they are valued by "paying" the the payout amount of the payout token.
  ///
  /// The same mechanic can be extended to include multiple pools at once. When a searcher notices
  /// that the sum of the protocol fees in multiple pools is greater than the payout amount, they
  /// can call this method to claim the fees from all of the pools in a single transaction.
  /// @param _claimInputs The array of claim input data. Each element contains
  /// the following:
  /// - `pool`: The Uniswap v3 pool from which protocol fees are collected.
  /// - `amount0Requested`: The amount of the pool's token0 to forward to the pool's collectProtocol
  ///   function. Its maximum value will be `protocolFees.token0 - 1`. Requesting more than the
  ///   maximum value will revert.
  /// - `amount1Requested`: The amount of the pool's token1 to forward to the pool's collectProtocol
  ///   function. Its maximum value will be `protocolFees.token1 - 1`. Requesting more than the
  ///   maximum value will revert.
  /// @return _claimOutputs The array of claim output data. Each element
  /// contains the following:
  /// - `pool`: The Uniswap v3 pool from which protocol fees were collected.
  /// - `amount0`: The amount of the pool's token0 collected.
  /// - `amount1`: The amount of the pool's token1 collected.
  /// @dev The `UniswapV3Pool contract allows claiming a maximum of the total accrued fees minus 1.
  /// We highly recommend checking the source code of the `UniswapV3Pool` contract in order to
  /// better understand the potential constraints of the forwarded params.
  /// @dev This function makes external calls to user-provided pool addresses. Future modifications
  /// should consider reentrancy implications.
  function claimFees(ClaimInputData[] calldata _claimInputs)
    external
    returns (ClaimOutputData[] memory _claimOutputs);
}
