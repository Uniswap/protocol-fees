// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";
import {ITokenJar} from "./ITokenJar.sol";

interface IReleaser {
    event ThresholdSet(uint256 newThreshold);
    event MaxAssetReleaseSet(uint256 newMaxAssetRelease);
    event ResourceSet(address indexed newResource);
    event ResourceReceiverSet(address indexed newResourceReceiver);
    event TokenJarSet(address indexed newTokenJar);
    event ReleaseHookSet(address indexed newReleaseHook);
    event Released(uint256 indexed nonce, address indexed recipient, Currency[] assets);

    error InvalidNonce();
    error TooManyAssets();

    function threshold() external view returns (uint256);
    function maxAssetRelease() external view returns (uint256);
    function nonce() external view returns (uint256);
    function resource() external view returns (address);
    function tokenJar() external view returns (address);
    function releaseHook() external view returns (address);

    function setThreshold(uint256 newThreshold) external;
    function setMaxAssetRelease(uint256 newMaxAssetRelease) external;
    function setResource(address newResource) external;
    function setTokenJar(address newTokenJar) external;
    function setReleaseHook(address newReleaseHook) external;
}
