# OPStackFirepitSource
[Git Source](https://github.com/Uniswap/phoenix-fees/blob/5ad4b18e2825646f5b8057eb618759de00281b9a/src/crosschain/OPStackFirepitSource.sol)

**Inherits:**
[FirepitSource](/technical-reference/abstract.FirepitSource)


## State Variables
### MESSENGER

```solidity
IL1CrossDomainMessenger public immutable MESSENGER;
```


### L2_TARGET

```solidity
address public immutable L2_TARGET;
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
  uint256,
  uint256 destinationNonce,
  Currency[] memory assets,
  address claimer,
  bytes memory addtlData
) internal override;
```

