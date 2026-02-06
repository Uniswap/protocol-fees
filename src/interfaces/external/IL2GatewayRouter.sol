// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IL2GatewayRouter
/// @notice Interface for Arbitrum's L2 Gateway Router for ERC20 token withdrawals
/// @dev Used to initiate withdrawals from Arbitrum L2 to Ethereum L1
interface IL2GatewayRouter {
  /// @notice Initiates a token withdrawal from Arbitrum L2 to Ethereum L1
  /// @dev The _maxGas and _gasPriceBid parameters are ignored for L2 to L1 withdrawals
  /// @param _l1Token The L1 (Ethereum) address of the token being withdrawn
  /// @param _to The destination address on L1
  /// @param _amount The amount of tokens to withdraw
  /// @param _data Additional data (typically empty for standard withdrawals)
  /// @return The encoded withdrawal ID
  function outboundTransfer(address _l1Token, address _to, uint256 _amount, bytes calldata _data)
    external
    payable
    returns (bytes memory);

  /// @notice Returns the gateway address for a specific token
  /// @param _token The L1 token address
  /// @return gateway The gateway address for the token
  function getGateway(address _token) external view returns (address gateway);

  /// @notice Calculates the L2 token address for a given L1 token
  /// @param l1ERC20 The L1 token address
  /// @return The corresponding L2 token address
  function calculateL2TokenAddress(address l1ERC20) external view returns (address);
}
