# Firepit
[Git Source](https://github.com/Uniswap/phoenix-fees/blob/d3a3001da4e227f1f508a23b1d3a5a569ef65604/src/releasers/Firepit.sol)

**Inherits:**
[ExchangeReleaser](/technical-reference/abstract.ExchangeReleaser)

An ExchangeReleaser with recipient set to the burn address address(0xdead) and a limit
on the number of currencies that can be released at any time.


## State Variables
### MAX_RELEASE_LENGTH
Maximum number of different assets that can be released in a single call


```solidity
uint256 public constant MAX_RELEASE_LENGTH = 20;
```


## Functions
### constructor


```solidity
constructor(address _resource, uint256 _threshold, address _assetSink)
  ExchangeReleaser(_resource, _threshold, _assetSink, address(0xdead));
```

### release

Releases assets to a specified recipient if the resource threshold is met


```solidity
function release(uint256 _nonce, Currency[] memory assets, address recipient) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nonce`|`uint256`|The nonce for the release, must equal to the contract nonce otherwise revert|
|`assets`|`Currency[]`|The list of assets to release, which may have length limits|
|`recipient`|`address`|The address to receive the released assets, paid out by Asset Sink|


## Errors
### TooManyAssets
Thrown when attempting to release too many assets at once


```solidity
error TooManyAssets();
```

