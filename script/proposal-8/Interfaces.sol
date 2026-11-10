// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @dev The subset of Morpho `VaultV2` this proposal touches. Source of the deployed vaults:
///      https://etherscan.io/address/0x5B453493D2328E7F747eb2e66446eFe707728be7#code
interface IVaultV2 {
  function owner() external view returns (address);
  function isSentinel(address account) external view returns (bool);
  /// @dev Owner only. Not timelocked.
  function setIsSentinel(address account, bool newIsSentinel) external;
}
