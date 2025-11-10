# TokenJar
[Git Source](https://github.com/Uniswap/protocol-fees/blob/05bb600bef88d196654e551c6a749d9e98fe3f0f/src/TokenJar.sol)

**Inherits:**
Owned, [ITokenJar](/Users/daniel/Documents/uniswap/contracts/protocol-fees/forge-docs/src/src/interfaces/ITokenJar.sol/interface.ITokenJar.md)

A singular destination for protocol fees

Fees accumulate passively in this contract from external sources.
Stored fees can be released by an authorized releaser contract.

**Note:**
security-contact: security@uniswap.org


## State Variables
### releaser
The releaser has exclusive access to the `release()` function


```solidity
address public releaser
```


## Functions
### onlyReleaser

Ensures only the releaser can call the release function


```solidity
modifier onlyReleaser() ;
```

### constructor

creates an token jar where the deployer is the initial owner
during deployment, the deployer SHOULD set the releaser address and
transfer ownership


```solidity
constructor() Owned(msg.sender);
```

### release

Release assets to a specified recipient

only callable by `releaser`


```solidity
function release(Currency[] calldata assets, address recipient) external onlyReleaser;
```

### setReleaser

Set the address of the IReleaser contract

only callabe by `owner`


```solidity
function setReleaser(address _releaser) external onlyOwner;
```

### receive


```solidity
receive() external payable;
```

