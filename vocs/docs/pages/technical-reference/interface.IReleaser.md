# IReleaser
[Git Source](https://github.com/Uniswap/phoenix-fees/blob/d3a3001da4e227f1f508a23b1d3a5a569ef65604/src/interfaces/IReleaser.sol)

**Inherits:**
[IResourceManager](/technical-reference/interface.IResourceManager), [INonce](/technical-reference/interface.INonce)


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
|`assets`|`Currency[]`|The list of assets to release, which may have length limits|
|`recipient`|`address`|The address to receive the released assets, paid out by Asset Sink|


