# VestingLib
[Git Source](https://github.com/Uniswap/phoenix-fees/blob/f7ccbcc4f1be2c8485a362f78f4f1ea34145b2b0/src/libraries/VestingLib.sol)

Library for vesting calculations

**Note:**
security-contact: security@uniswap.org


## Functions
### sub

if b is negative: a - (-b)
otherwise: a - b


```solidity
function sub(uint256 a, int256 b) internal pure returns (uint256);
```

### add


```solidity
function add(int256 a, uint256 b) internal pure returns (int256);
```

