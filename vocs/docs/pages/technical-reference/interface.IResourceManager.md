# IResourceManager
[Git Source](https://github.com/Uniswap/phoenix-fees/blob/5ad4b18e2825646f5b8057eb618759de00281b9a/src/interfaces/base/IResourceManager.sol)

The interface for managing the resource token and its threshold value


## Functions
### RESOURCE

The resource token required by parent IReleaser


```solidity
function RESOURCE() external view returns (ERC20);
```

### RESOURCE_RECIPIENT

The recipient of the `RESOURCE` tokens


```solidity
function RESOURCE_RECIPIENT() external view returns (address);
```

### threshold

The minimum threshold of `RESOURCE` tokens required to perform a release


```solidity
function threshold() external view returns (uint256);
```

### thresholdSetter

The address authorized to set the `threshold` value


```solidity
function thresholdSetter() external view returns (address);
```

### setThresholdSetter

Set the address authorized to set the `threshold` value

*only callable by `owner`*


```solidity
function setThresholdSetter(address newThresholdSetter) external;
```

### setThreshold

Set the minimum threshold of `RESOURCE` tokens required to perform a release

*only callable by `thresholdSetter`*


```solidity
function setThreshold(uint256 newThreshold) external;
```

## Errors
### Unauthorized
Thrown when an unauthorized address attempts to call a restricted function


```solidity
error Unauthorized();
```

