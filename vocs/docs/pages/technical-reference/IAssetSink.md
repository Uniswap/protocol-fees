# IAssetSink
[Git Source](https://github.com/Uniswap/phoenix-fees/blob/0a207f54810ba606b9e24257932782cb232b83b8/src/interfaces/IAssetSink.sol)

The interface for releasing assets from the contract


## Functions
### releaser

*The releaser has exclusive access to the `release()` function*


```solidity
function releaser() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|Address of the current IReleaser|


### setReleaser

Set the address of the IReleaser contract

*only callabe by `owner`*


```solidity
function setReleaser(address _releaser) external;
```

### release

Release assets to a specified recipient

*only callable by `releaser`*


```solidity
function release(Currency[] calldata assets, address recipient) external;
```

## Errors
### Unauthorized
Thrown when an unauthorized address attempts to call a restricted function


```solidity
error Unauthorized();
```

