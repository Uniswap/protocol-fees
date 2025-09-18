# IAssetSink
[Git Source](https://github.com/Uniswap/phoenix-fees/blob/d3a3001da4e227f1f508a23b1d3a5a569ef65604/src/interfaces/IAssetSink.sol)

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

## Events
### FeesClaimed
Emitted when asset fees are successfully claimed


```solidity
event FeesClaimed(Currency indexed asset, address indexed recipient, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`Currency`|Address of the asset that was claimed|
|`recipient`|`address`|Address that received the assets|
|`amount`|`uint256`|Amount of fees transferred to the recipient|

## Errors
### Unauthorized
Thrown when an unauthorized address attempts to call a restricted function


```solidity
error Unauthorized();
```

