# INonce
[Git Source](https://github.com/Uniswap/phoenix-fees/blob/5ad4b18e2825646f5b8057eb618759de00281b9a/src/interfaces/base/INonce.sol)


## Functions
### nonce


```solidity
function nonce() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The contract's nonce|


## Errors
### InvalidNonce
Thrown when a user-provided nonce is not equal to the contract's nonce


```solidity
error InvalidNonce();
```

