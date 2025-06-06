// SPDX-License-Identifier: AGPL-3.0-only
// slither-disable-start reentrancy-benign
pragma solidity ^0.8.23;

contract DeployOwnerInput {
  address constant UNISTAKER_ADDRESS = 0x6cA69b90394D31fF0a233b3F422CF15411567FA8;
  address constant UNISWAP_V3_FACTORY_ADDRESS = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
  address constant UNISWAP_GOVERNOR_TIMELOCK = 0x1a9C8182C09F50C8318d769245beA52c32BE35BC;
  address constant PAYOUT_TOKEN_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
  uint8 INITIAL_GLOBAL_PROTOCOL_FEE_DENOMINATOR = 5; // 1/5 = 20%
  uint256 constant PAYOUT_AMOUNT = 10e18; // 10 (WETH)
}
