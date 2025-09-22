# V3FeeController
[Git Source](https://github.com/Uniswap/phoenix-fees/blob/0a207f54810ba606b9e24257932782cb232b83b8/src/feeControllers/V3FeeController.sol)

**Inherits:**
[IV3FeeController](/technical-reference/IV3FeeController), Owned

A contract that allows the setting and collecting of protocol fees per pool, and adding
new fee tiers to the Uniswap V3 Factory.

*This contract is ownable. The owner can set the merkle root for proving protocol fee
amounts per pool, set new fee tiers on Uniswap V3, and change the owner of this contract.
Note that this contract will be the set owner on the Uniswap V3 Factory.*

**Note:**
security-contact: security@uniswap.org


## State Variables
### FACTORY

```solidity
IUniswapV3Factory public immutable FACTORY;
```


### ASSET_SINK

```solidity
address public immutable ASSET_SINK;
```


### merkleRoot

```solidity
bytes32 public merkleRoot;
```


### feeSetter

```solidity
address public feeSetter;
```


### defaultFees
Returns the default fee value for a given fee tier.


```solidity
mapping(uint24 feeTier => uint8 defaultFeeValue) public defaultFees;
```


## Functions
### onlyFeeSetter

Ensures only the fee setter can call the setMerkleRoot and setDefaultFeeByFeeTier
functions


```solidity
modifier onlyFeeSetter();
```

### constructor

*At construction, the fee setter defaults to 0 and its on the owner to set.*


```solidity
constructor(address _factory, address _assetSink) Owned(msg.sender);
```

### enableFeeAmount

Enables a new fee tier on the Uniswap V3 Factory.

*Only callable by `owner`*


```solidity
function enableFeeAmount(uint24 fee, int24 tickSpacing) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`fee`|`uint24`||
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
function setMerkleRoot(bytes32 _merkleRoot) external onlyFeeSetter;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_merkleRoot`|`bytes32`|The new merkle root to set.|


### setDefaultFeeByFeeTier

Sets the default fee value for a specific fee tier.


```solidity
function setDefaultFeeByFeeTier(uint24 feeTier, uint8 defaultFeeValue) external onlyFeeSetter;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`feeTier`|`uint24`|The fee tier, expressed in pips, to set the default fee for.|
|`defaultFeeValue`|`uint8`|The default fee value to set, expressed as the denominator on the inclusive interval [4, 10]. The fee value is packed (token1Fee \<\< 4 \| token0Fee)|


### triggerFeeUpdate

Triggers a fee update for a single pool with merkle proof verification.


```solidity
function triggerFeeUpdate(address pool, bytes32[] calldata proof) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pool`|`address`|The pool address to update the fee for.|
|`proof`|`bytes32[]`||


### setFeeSetter

Sets a new fee setter address.


```solidity
function setFeeSetter(address newFeeSetter) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newFeeSetter`|`address`|The new address authorized to set fees and merkle roots.|


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


### _setProtocolFee


```solidity
function _setProtocolFee(address pool) internal;
```

### _doubleHash


```solidity
function _doubleHash(address pool) internal pure returns (bytes32 poolHash);
```

