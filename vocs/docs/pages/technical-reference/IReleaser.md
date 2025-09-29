# IReleaser
[Git Source](https://github.com/Uniswap/phoenix-fees/blob/0a207f54810ba606b9e24257932782cb232b83b8/src/interfaces/IReleaser.sol)

**Inherits:**
[IResourceManager](/technical-reference/IResourceManager), [INonce](/technical-reference/INonce)


## Functions
### ASSET_SINK


```solidity
function ASSET_SINK() external view returns (IAssetSink);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IAssetSink`|Address of the Asset Sink contract that will release the assets|


### release

Releases assets to a specified recipient if the resource threshold is met


```solidity
function release(uint256 _nonce, Currency[] memory assets, address recipient) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nonce`|`uint256`|The nonce for the release, must equal to the contract nonce otherwise revert|
|`assets`|`Currency[]`|The list of assets (addresses) to release, which may have length limits Native tokens (Ether) are represented as the zero address|
|`recipient`|`address`|The address to receive the released assets, paid out by Asset Sink|


