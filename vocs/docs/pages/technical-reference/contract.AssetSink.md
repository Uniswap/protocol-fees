# AssetSink
[Git Source](https://github.com/Uniswap/phoenix-fees/blob/5ad4b18e2825646f5b8057eb618759de00281b9a/src/AssetSink.sol)

**Inherits:**
Owned, [IAssetSink](/technical-reference/interface.IAssetSink)

Sink for protocol fees

*Fees accumulate passively in this contract from external sources.
Stored fees can be released by authorized releaser contracts.*


## State Variables
### releaser
*The releaser has exclusive access to the `release()` function*


```solidity
address public releaser;
```


## Functions
### onlyReleaser

Ensures only the releaser can call the release function


```solidity
modifier onlyReleaser();
```

### constructor

Creates a new AssetSink with the specified releaser


```solidity
constructor() Owned(msg.sender);
```

### release

Release assets to a specified recipient

*only callable by `releaser`*


```solidity
function release(Currency[] calldata assets, address recipient) external onlyReleaser;
```

### setReleaser

Set the address of the IReleaser contract

*only callabe by `owner`*


```solidity
function setReleaser(address _releaser) external onlyOwner;
```

### receive


```solidity
receive() external payable;
```

