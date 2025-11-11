// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {ITokenJar} from "./ITokenJar.sol";
import {IResourceManager} from "./base/IResourceManager.sol";
import {INonce} from "./base/INonce.sol";

interface IReleaser is IResourceManager, INonce {
  /// @notice Thrown when attempting to release too many assets at once
  error TooManyAssets();

  /// @return Address of the Token Jar contract that will release the assets
  function TOKEN_JAR() external view returns (ITokenJar);

  /// @notice Releases assets to a specified recipient if the resource threshold is met
  /// @param _nonce The nonce for the release, must equal to the contract nonce otherwise revert
  /// @param assets The list of assets (addresses) to release, which may have length limits
  /// Native tokens (Ether) are represented as the zero address
  /// @param recipient The address to receive the released assets, paid out by Token Jar
  function release(uint256 _nonce, Currency[] calldata assets, address recipient) external;
}
