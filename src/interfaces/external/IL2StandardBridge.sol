// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IL2StandardBridge {
  /// @notice Sends ETH to a receiver's address on the other chain. Note that if ETH is sent to a
  ///         smart contract and the call fails, the ETH will be temporarily locked in the
  ///         StandardBridge on the other chain until the call is replayed. If the call cannot be
  ///         replayed with any amount of gas (call always reverts), then the ETH will be
  ///         permanently locked in the StandardBridge on the other chain. ETH will also
  ///         be locked if the receiver is the other bridge, because finalizeBridgeETH will revert
  ///         in that case.
  /// @param _to          Address of the receiver.
  /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
  /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
  ///                     not be triggered with this data, but it will be emitted and can be used
  ///                     to identify the transaction.
  function bridgeETHTo(address _to, uint32 _minGasLimit, bytes calldata _extraData) external payable;

  /// @notice Initiates a withdrawal from L2 to L1 to a target account on L1.
  ///         Note that if ETH is sent to a contract on L1 and the call fails, then that ETH will
  ///         be locked in the L1StandardBridge. ETH may be recoverable if the call can be
  ///         successfully replayed by increasing the amount of gas supplied to the call. If the
  ///         call will fail for any amount of gas, then the ETH will be locked permanently.
  ///         This function only works with OptimismMintableERC20 tokens or ether. Use the
  ///         `bridgeERC20To` function to bridge native L2 tokens to L1.
  ///         Subject to be deprecated in the future.
  /// @param _l2Token     Address of the L2 token to withdraw.
  /// @param _to          Recipient account on L1.
  /// @param _amount      Amount of the L2 token to withdraw.
  /// @param _minGasLimit Minimum gas limit to use for the transaction.
  /// @param _extraData   Extra data attached to the withdrawal.
  function withdrawTo(
    address _l2Token,
    address _to,
    uint256 _amount,
    uint32 _minGasLimit,
    bytes calldata _extraData
  ) external;
}
