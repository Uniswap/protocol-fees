# INonce
[Git Source](https://github.com/Uniswap/phoenix-fees/blob/d3a3001da4e227f1f508a23b1d3a5a569ef65604/src/interfaces/base/INonce.sol)


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

