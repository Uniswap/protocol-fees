# ResourceManager
[Git Source](https://github.com/Uniswap/phoenix-fees/blob/0a207f54810ba606b9e24257932782cb232b83b8/src/base/ResourceManager.sol)

**Inherits:**
[IResourceManager](/technical-reference/IResourceManager), Owned

A contract that holds immutable state for the resource token and the resource recipient
address. It also maintains logic for managing the threshold of the resource token.


## State Variables
### threshold
The minimum threshold of `RESOURCE` tokens required to perform a release


```solidity
uint256 public threshold;
```


### thresholdSetter
The address authorized to set the `threshold` value


```solidity
address public thresholdSetter;
```


### RESOURCE
The resource token required by parent IReleaser


```solidity
ERC20 public immutable RESOURCE;
```


### RESOURCE_RECIPIENT
The recipient of the `RESOURCE` tokens


```solidity
address public immutable RESOURCE_RECIPIENT;
```


## Functions
### onlyThresholdSetter

Ensures only the threshold setter can call the setThreshold function


```solidity
modifier onlyThresholdSetter();
```

### constructor

*At construction the thresholdSetter defaults to 0 and its on the owner to set.*


```solidity
constructor(address _resource, uint256 _threshold, address _owner, address _recipient)
  Owned(_owner);
```

### setThresholdSetter

Set the address authorized to set the `threshold` value

*only callable by `owner`*


```solidity
function setThresholdSetter(address _thresholdSetter) external onlyOwner;
```

### setThreshold

Set the minimum threshold of `RESOURCE` tokens required to perform a release

*only callable by `thresholdSetter`*


```solidity
function setThreshold(uint256 _threshold) external onlyThresholdSetter;
```

