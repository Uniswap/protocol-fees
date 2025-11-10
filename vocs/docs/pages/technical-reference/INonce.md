# INonce
[Git Source](https://github.com/Uniswap/protocol-fees/blob/05bb600bef88d196654e551c6a749d9e98fe3f0f/src/interfaces/base/INonce.sol)


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

