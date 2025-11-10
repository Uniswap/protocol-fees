# OPStackFirepitSource
[Git Source](https://github.com/Uniswap/protocol-fees/blob/05bb600bef88d196654e551c6a749d9e98fe3f0f/src/crosschain/OPStackFirepitSource.sol)

**Inherits:**
[FirepitSource](/Users/daniel/Documents/uniswap/contracts/protocol-fees/forge-docs/src/src/crosschain/FirepitSource.sol/abstract.FirepitSource.md)


## State Variables
### MESSENGER

```solidity
IL1CrossDomainMessenger public immutable MESSENGER
```


### L2_TARGET

```solidity
address public immutable L2_TARGET
```


## Functions
### constructor


```solidity
constructor(address _resource, address _messenger, address _l2Target)
  FirepitSource(msg.sender, _resource);
```

### _sendReleaseMessage


```solidity
function _sendReleaseMessage(
  uint256, // bridgeId
  uint256 destinationNonce,
  Currency[] calldata assets,
  address claimer,
  bytes memory addtlData
) internal override;
```

