// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {IReleaser} from "./interfaces/IReleaser.sol";
import {IReleaseHook} from "./interfaces/IReleaseHook.sol";
import {ITokenJar} from "./interfaces/ITokenJar.sol";

import {Owned} from "solmate/src/auth/Owned.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract Releaser is Owned(msg.sender), IReleaser {
    uint256 public threshold;
    uint256 public maxAssetRelease;
    uint256 public nonce;

    address public resource;
    address public tokenJar;
    address public releaseHook;

    function release(uint256 expectedNonce, Currency[] calldata assets, address assetsReceiver) public payable {
        require(assets.length <= maxAssetRelease, TooManyAssets());

        require(nonce == expectedNonce, InvalidNonce());

        nonce += 1;

        ERC20(resource).transferFrom(msg.sender, releaseHook, threshold);

        IReleaseHook(releaseHook).afterRelease{value: msg.value}(resource, threshold);

        ITokenJar(tokenJar).release(assets, assetsReceiver);

        emit Released(nonce, assetsReceiver, assets);
    }

    function setThreshold(uint256 newThreshold) public onlyOwner {
        threshold = newThreshold;
        emit ThresholdSet(newThreshold);
    }

    function setMaxAssetRelease(uint256 newMaxAssetRelease) public onlyOwner {
        maxAssetRelease = newMaxAssetRelease;
        emit MaxAssetReleaseSet(newMaxAssetRelease);
    }

    function setResource(address newResource) public onlyOwner {
        resource = newResource;
        emit ResourceSet(newResource);
    }

    function setTokenJar(address newTokenJar) public onlyOwner {
        tokenJar = newTokenJar;
        emit TokenJarSet(newTokenJar);
    }

    function setReleaseHook(address newReleaseHook) public onlyOwner {
        releaseHook = newReleaseHook;
        emit ReleaseHookSet(newReleaseHook);
    }
}
