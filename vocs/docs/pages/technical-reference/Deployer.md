# Deployer
[Git Source](https://github.com/Uniswap/phoenix-fees/blob/38e66458d36a90d45d2da802d97629a7d8137a57/src/Deployer.sol)


## State Variables
### ASSET_SINK

```solidity
IAssetSink public immutable ASSET_SINK;
```


### RELEASER

```solidity
IReleaser public immutable RELEASER;
```


### FEE_ADAPTER

```solidity
IV3FeeAdapter public immutable FEE_ADAPTER;
```


### UNI_MINTER

```solidity
IUNIMinter public immutable UNI_MINTER;
```


### RESOURCE

```solidity
address public constant RESOURCE = 0x1000000000000000000000000000000000000000;
```


### THRESHOLD

```solidity
uint256 public constant THRESHOLD = 69_420;
```


### V3_FACTORY

```solidity
IUniswapV3Factory public constant V3_FACTORY =
  IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
```


### SALT_ASSET_SINK

```solidity
bytes32 constant SALT_ASSET_SINK = 0;
```


### SALT_RELEASER

```solidity
bytes32 constant SALT_RELEASER = 0;
```


### SALT_FEE_ADAPTER

```solidity
bytes32 constant SALT_FEE_ADAPTER = 0;
```


## Functions
### constructor

1. Deploy the AssetSink
3. Set the releaser on the asset sink.
4. Update the owner on the asset sink.
RELEASER:
2. Deploy the Releaser.
5. Update the thresholdSetter on the releaser to the owner.
6. Update the owner on the releaser.
FEE_ADAPTER:
7. Deploy the FeeAdapter.
8. Update the feeSetter to the owner.
9. Store fee tiers.
10. Update the owner on the fee adapter.
UNIMinter
11. Deploy the UNIMinter
- To enable the UNIMinter, the owner must call `setMinter` on the UNI contract


```solidity
constructor();
```

