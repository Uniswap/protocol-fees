# IV3FeeController
[Git Source](https://github.com/Uniswap/phoenix-fees/blob/d3a3001da4e227f1f508a23b1d3a5a569ef65604/src/interfaces/IV3FeeController.sol)


## Functions
### ASSET_SINK


```solidity
function ASSET_SINK() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address where collected fees are sent.|


### FACTORY


```solidity
function FACTORY() external view returns (IUniswapV3Factory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IUniswapV3Factory`|The Uniswap V3 Factory contract.|


### merkleRoot


```solidity
function merkleRoot() external view returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|The current merkle root used to designate which pools have a fee enabled|


### feeSetter


```solidity
function feeSetter() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The authorized address to set fees-by-fee-tier AND the merkle root|


### defaultFees

Returns the default fee value for a given fee tier.


```solidity
function defaultFees(uint24 feeTier) external view returns (uint8 defaultFeeValue);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`feeTier`|`uint24`|The fee tier to query.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`defaultFeeValue`|`uint8`|The default fee value expressed as the denominator on the inclusive interval [4, 10]. The fee value is packed (token1Fee << 4 | token0Fee)|


### enableFeeAmount

Enables a new fee tier on the Uniswap V3 Factory.

*Only callable by `owner`*


```solidity
function enableFeeAmount(uint24 newFeeTier, int24 tickSpacing) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newFeeTier`|`uint24`|The fee tier to enable.|
|`tickSpacing`|`int24`|The corresponding tick spacing for the new fee tier.|


### collect

Collects protocol fees from the specified pools to the designated `ASSET_SINK`


```solidity
function collect(CollectParams[] calldata collectParams)
  external
  returns (Collected[] memory amountsCollected);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collectParams`|`CollectParams[]`|Array of collection parameters for each pool.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amountsCollected`|`Collected[]`|Array of collected amounts for each pool.|


### setMerkleRoot

Sets the merkle root used for designating which pools have the fee enabled.

*Only callable by `feeSetter`*


```solidity
function setMerkleRoot(bytes32 _merkleRoot) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_merkleRoot`|`bytes32`|The new merkle root to set.|


### setDefaultFeeByFeeTier

Sets the default fee value for a specific fee tier.


```solidity
function setDefaultFeeByFeeTier(uint24 feeTier, uint8 defaultFeeValue) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`feeTier`|`uint24`|The fee tier, expressed in pips, to set the default fee for.|
|`defaultFeeValue`|`uint8`|The default fee value to set, expressed as the denominator on the inclusive interval [4, 10]. The fee value is packed (token1Fee << 4 | token0Fee)|


### triggerFeeUpdate

Triggers a fee update for a single pool with merkle proof verification.


```solidity
function triggerFeeUpdate(address pool, bytes32[] calldata merkleProof) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pool`|`address`|The pool address to update the fee for.|
|`merkleProof`|`bytes32[]`|The merkle proof corresponding to the set merkle root.|


### batchTriggerFeeUpdate

Triggers fee updates for multiple pools with batch merkle proof verification.


```solidity
function batchTriggerFeeUpdate(
  address[] calldata pools,
  bytes32[] calldata proof,
  bool[] calldata proofFlags
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pools`|`address[]`|The pool addresses to update fees for.|
|`proof`|`bytes32[]`|The merkle proof corresponding to the set merkle root.|
|`proofFlags`|`bool[]`|The flags for the merkle proof verification.|


### setFeeSetter

Sets a new fee setter address.


```solidity
function setFeeSetter(address newFeeSetter) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newFeeSetter`|`address`|The new address authorized to set fees and merkle roots.|


## Errors
### AmountCollectedTooLow
Thrown when the amount collected is less than the amount expected.


```solidity
error AmountCollectedTooLow(uint256 amountCollected, uint256 amountExpected);
```

### InvalidProof
Thrown when the merkle proof is invalid.


```solidity
error InvalidProof();
```

### InvalidFeeTier
Thrown when trying to set a default fee for a non-enabled fee tier.


```solidity
error InvalidFeeTier();
```

### Unauthorized
Thrown when an unauthorized address attempts to call a restricted function


```solidity
error Unauthorized();
```

## Structs
### CollectParams
The input parameters for the collection.


```solidity
struct CollectParams {
  address pool;
  uint128 amount0Requested;
  uint128 amount1Requested;
}
```

### Collected
The returned amounts of token0 and token1 that are collected.


```solidity
struct Collected {
  uint128 amount0Collected;
  uint128 amount1Collected;
}
```

