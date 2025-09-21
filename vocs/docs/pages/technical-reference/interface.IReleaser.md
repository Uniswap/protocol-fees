# IReleaser
[Git Source](https://github.com/Uniswap/phoenix-fees/blob/5ad4b18e2825646f5b8057eb618759de00281b9a/src/interfaces/IReleaser.sol)

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
|`assets`|`Currency[]`|The list of assets (addresses) to release, which may have length limits Native tokens (Ether) are represented as the zero address|
|`recipient`|`address`|The address to receive the released assets, paid out by Asset Sink|


