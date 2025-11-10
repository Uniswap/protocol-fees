# IOwned
[Git Source](https://github.com/Uniswap/protocol-fees/blob/05bb600bef88d196654e551c6a749d9e98fe3f0f/src/interfaces/base/IOwned.sol)

Interface for Solmate's Owned.sol contract


## Functions
### owner


```solidity
function owner() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|owner of the contract|


### transferOwnership

Transfers ownership of the contract to a new address


```solidity
function transferOwnership(address newOwner) external;
```

