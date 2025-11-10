# FirepitDestination
[Git Source](https://github.com/Uniswap/protocol-fees/blob/05bb600bef88d196654e551c6a749d9e98fe3f0f/src/crosschain/FirepitDestination.sol)

**Inherits:**
[Nonce](/Users/daniel/Documents/uniswap/contracts/protocol-fees/forge-docs/src/src/base/Nonce.sol/abstract.Nonce.md), Owned

a contract for receiving crosschain messages. Validates messages and releases assets
from the TokenJar


## State Variables
### allowableSource
the source contract that is allowed to originate messages to this contract i.e.
FirepitSource

updatable by owner


```solidity
address public allowableSource
```


### allowableCallers
the local contract(s) that are allowed to call this contract, i.e. Message Relayers

updatable by owner


```solidity
mapping(address callers => bool allowed) public allowableCallers
```


### TOKEN_JAR

```solidity
TokenJar public immutable TOKEN_JAR
```


### MINIMUM_RELEASE_GAS

```solidity
uint256 public constant MINIMUM_RELEASE_GAS = 100_000
```


## Functions
### constructor


```solidity
constructor(address _owner, address _tokenJar) Owned(_owner);
```

### onlyAllowed


```solidity
modifier onlyAllowed() ;
```

### claimTo

Calls Token Jar to release assets to a destination

only callable by the messenger via the authorized L1 source contract


```solidity
function claimTo(uint256 _nonce, Currency[] calldata assets, address claimer)
  external
  onlyAllowed
  handleNonce(_nonce);
```

### setAllowableCallers


```solidity
function setAllowableCallers(address callers, bool isAllowed) external onlyOwner;
```

### setAllowableSource


```solidity
function setAllowableSource(address source) external onlyOwner;
```

## Events
### FailedRelease

```solidity
event FailedRelease(uint256 indexed _nonce, address indexed _claimer);
```

