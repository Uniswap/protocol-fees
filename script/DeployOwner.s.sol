// SPDX-License-Identifier: AGPL-3.0-only
// slither-disable-start reentrancy-benign
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Script} from "forge-std/Script.sol";

import {DeployOwnerInput} from "script/DeployOwnerInput.sol";
import {V3FeeManager} from "src/V3FeeManager.sol";
import {IUniswapV3FactoryOwnerActions} from "src/interfaces/IUniswapV3FactoryOwnerActions.sol";

contract DeployOwner is Script, DeployOwnerInput {
  uint256 deployerPrivateKey;

  function setUp() public {
    deployerPrivateKey = vm.envOr(
      "DEPLOYER_PRIVATE_KEY",
      uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
    );
  }

  function run() public returns (V3FeeManager) {
    vm.startBroadcast(deployerPrivateKey);

    // Deploy a new owner for the V3 factory owner actions contract.
    V3FeeManager v3FeeManager = new V3FeeManager(
      UNISWAP_GOVERNOR_TIMELOCK,
      IUniswapV3FactoryOwnerActions(UNISWAP_V3_FACTORY_ADDRESS),
      IERC20(PAYOUT_TOKEN_ADDRESS),
      PAYOUT_AMOUNT,
      INITIAL_GLOBAL_PROTOCOL_FEE_DENOMINATOR,
      UNISTAKER_ADDRESS
    );

    // TODO Governance will need to change the owner of the
    // UNISWAP_V3_FACTORY_ADDRESS so that v3FeeManager is the new owner.

    // TODO Governance will need to add a new rewardNotifier to Unistaker via
    // Unistaker.setRewardNotifier (either v3FeeManager or whatever address is
    // going to pool rewards).

    // TODO Governance will need to disable the old owner as a UniStaker reward
    // notifier.
    // UniStaker.setRewardNotifier(address(_oldV3FeeManager), false);

    vm.stopBroadcast();

    return v3FeeManager;
  }
}
