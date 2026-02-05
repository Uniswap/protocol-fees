// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IProtocolFees} from "v4-core/interfaces/IProtocolFees.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {V4FeeAdapter} from "../src/feeAdapters/V4FeeAdapter.sol";

struct ProposalAction {
  address target;
  uint256 value;
  string signature;
  bytes data;
}

/// @title V4FeeSwitchProposal
/// @notice Governance proposal to activate protocol fees on Uniswap V4
/// @dev Requires V4FeeAdapter to be deployed first via V4MainnetDeployer.
///      This proposal:
///      1. Sets the V4FeeAdapter as the protocol fee controller on the PoolManager
///      2. Configures default and tier-based protocol fees
///      3. Applies fees to a set of initial pools
contract V4FeeSwitchProposal is Script, StdAssertions {
  using PoolIdLibrary for PoolKey;

  /// @notice The V4 PoolManager on mainnet
  IPoolManager public constant POOL_MANAGER = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);

  /// @notice GovernorBravo contract for submitting proposals
  IGovernorBravo internal constant GOVERNOR_BRAVO = IGovernorBravo(0x408ED6354d4973f66138C91495F2f2FCbd8724C3);

  // ═══════════════════════════════════════════════════════════════
  //                      FEE CONFIGURATION
  // ═══════════════════════════════════════════════════════════════
  //
  // Fee ratios match V3 mainnet configuration:
  // - Default ratio: 1/4 of LP fee
  // - 0.30% and 1.00% tiers: 1/6 of LP fee
  //
  // V4 protocol fees are in pips (1/1_000_000). Max is 1000 pips (0.1%) per direction.

  /// @notice Default protocol fee for unknown tiers (1/4 of a typical 0.30% tier = 750 pips)
  /// @dev This is a fallback; most pools should match a known tier override
  uint24 public constant DEFAULT_PROTOCOL_FEE = 750;

  // Fee tier overrides (LP fee tier → protocol fee in pips)
  // Ratio: protocol_fee = lp_fee / N, where N is 4 (default) or 6 (high fee tiers)
  uint24 public constant TIER_8_FEE = 2; // 0.0008% / 4 = 0.0002% = 2 pips
  uint24 public constant TIER_10_FEE = 3; // 0.001% / 4 = 0.00025% ≈ 3 pips
  uint24 public constant TIER_45_FEE = 11; // 0.0045% / 4 = 0.001125% ≈ 11 pips
  uint24 public constant TIER_100_FEE = 25; // 0.01% / 4 = 0.0025% = 25 pips
  uint24 public constant TIER_500_FEE = 125; // 0.05% / 4 = 0.0125% = 125 pips
  uint24 public constant TIER_3000_FEE = 500; // 0.30% / 6 = 0.05% = 500 pips
  uint24 public constant TIER_10000_FEE = 1000; // 1.00% / 6 = 0.167% → capped at 1000 pips (0.1%)

  string internal constant PROPOSAL_DESCRIPTION = "# V4 Fee Switch Proposal\n\n"
    "This proposal activates protocol fees on Uniswap V4, matching the fee structure "
    "established for V3 in the UNIfication proposal.\n\n"
    "## Actions\n\n"
    "1. Set the V4FeeAdapter as the protocol fee controller on the V4 PoolManager\n"
    "2. Set a default protocol fee for pools without specific tier overrides\n"
    "3. Configure tier-based protocol fees matching V3 ratios\n"
    "4. Apply fees to initial set of high-volume V4 pools\n\n"
    "## Fee Structure\n\n"
    "Protocol fees are calculated as a fraction of the LP fee tier:\n"
    "- **1/4 ratio** for low-fee tiers (<=0.05%)\n"
    "- **1/6 ratio** for high-fee tiers (0.30% and 1.00%)\n\n"
    "| LP Fee Tier | Ratio | Protocol Fee |\n"
    "| ----------- | ----- | ------------ |\n"
    "| 0.0008% | 1/4 | 0.0002% (2 pips) |\n"
    "| 0.001% | 1/4 | 0.00025% (3 pips) |\n"
    "| 0.0045% | 1/4 | 0.00113% (11 pips) |\n"
    "| 0.01% | 1/4 | 0.0025% (25 pips) |\n"
    "| 0.05% | 1/4 | 0.0125% (125 pips) |\n"
    "| 0.30% | 1/6 | 0.05% (500 pips) |\n"
    "| 1.00% | 1/6 | 0.10% (1000 pips)* |\n\n"
    "*Capped at V4 maximum of 0.1% (1000 pips)\n\n"
    "All protocol fees flow to the TokenJar and can only be released via UNI burn.\n";

  function setUp() public {}

  /// @notice Generate proposal actions for the V4 fee switch
  /// @param adapter The deployed V4FeeAdapter
  /// @param poolsToActivate Array of pool keys to activate fees on
  function generateActions(V4FeeAdapter adapter, PoolKey[] memory poolsToActivate)
    public
    view
    returns (ProposalAction[] memory actions)
  {
    // Calculate number of actions:
    // 1. Set protocol fee controller
    // 2. Set default fee
    // 3-9. Set fee tier overrides (7 tiers)
    // 10. Batch apply fees to pools
    uint256 numActions = 10;
    actions = new ProposalAction[](numActions);

    // Action 0: Set the V4FeeAdapter as the protocol fee controller
    actions[0] = ProposalAction({
      target: address(POOL_MANAGER),
      value: 0,
      signature: "",
      data: abi.encodeCall(IProtocolFees.setProtocolFeeController, (address(adapter)))
    });

    // Action 1: Set default protocol fee
    actions[1] = ProposalAction({
      target: address(adapter),
      value: 0,
      signature: "",
      data: abi.encodeCall(adapter.setDefaultFee, (DEFAULT_PROTOCOL_FEE))
    });

    // Action 2-8: Set fee tier overrides
    actions[2] = ProposalAction({
      target: address(adapter),
      value: 0,
      signature: "",
      data: abi.encodeCall(adapter.setFeeTierOverride, (8, TIER_8_FEE))
    });

    actions[3] = ProposalAction({
      target: address(adapter),
      value: 0,
      signature: "",
      data: abi.encodeCall(adapter.setFeeTierOverride, (10, TIER_10_FEE))
    });

    actions[4] = ProposalAction({
      target: address(adapter),
      value: 0,
      signature: "",
      data: abi.encodeCall(adapter.setFeeTierOverride, (45, TIER_45_FEE))
    });

    actions[5] = ProposalAction({
      target: address(adapter),
      value: 0,
      signature: "",
      data: abi.encodeCall(adapter.setFeeTierOverride, (100, TIER_100_FEE))
    });

    actions[6] = ProposalAction({
      target: address(adapter),
      value: 0,
      signature: "",
      data: abi.encodeCall(adapter.setFeeTierOverride, (500, TIER_500_FEE))
    });

    actions[7] = ProposalAction({
      target: address(adapter),
      value: 0,
      signature: "",
      data: abi.encodeCall(adapter.setFeeTierOverride, (3000, TIER_3000_FEE))
    });

    actions[8] = ProposalAction({
      target: address(adapter),
      value: 0,
      signature: "",
      data: abi.encodeCall(adapter.setFeeTierOverride, (10000, TIER_10000_FEE))
    });

    // Action 9: Batch apply fees to initial pools
    actions[9] = ProposalAction({
      target: address(adapter),
      value: 0,
      signature: "",
      data: abi.encodeCall(adapter.batchApplyFees, (poolsToActivate))
    });
  }

  /// @notice Run the proposal simulation with prank (for testing)
  /// @param adapter The deployed V4FeeAdapter
  /// @param poolsToActivate Array of pool keys to activate fees on
  /// @param executor The address executing the proposal (e.g., timelock)
  function runPranked(V4FeeAdapter adapter, PoolKey[] memory poolsToActivate, address executor) public {
    vm.startPrank(executor);
    ProposalAction[] memory actions = generateActions(adapter, poolsToActivate);
    for (uint256 i = 0; i < actions.length; i++) {
      ProposalAction memory action = actions[i];
      (bool success,) = action.target.call{value: action.value}(action.data);
      require(success, string.concat("Action ", vm.toString(i), " failed"));
    }
    vm.stopPrank();
  }

  /// @notice Submit the proposal to GovernorBravo
  /// @param adapter The deployed V4FeeAdapter
  /// @param poolsToActivate Array of pool keys to activate fees on
  function run(V4FeeAdapter adapter, PoolKey[] memory poolsToActivate) public {
    vm.startBroadcast();

    ProposalAction[] memory actions = generateActions(adapter, poolsToActivate);

    console2.log("Calldata details:");
    for (uint256 i = 0; i < actions.length; i++) {
      ProposalAction memory action = actions[i];
      assertTrue(action.target != address(0));
      console2.log("Action #", i);
      console2.log("Target", action.target);
      console2.log("Value", action.value);
      console2.log("Signature");
      console2.log(action.signature);
      console2.log("Calldata", i);
      console2.logBytes(action.data);
      console2.log("--------------------------------");
    }

    console2.log("Description:");
    console2.log(PROPOSAL_DESCRIPTION);

    // Prepare GovernorBravo propose() parameters
    address[] memory targets = new address[](actions.length);
    uint256[] memory values = new uint256[](actions.length);
    string[] memory signatures = new string[](actions.length);
    bytes[] memory calldatas = new bytes[](actions.length);
    for (uint256 i = 0; i < actions.length; i++) {
      ProposalAction memory action = actions[i];
      targets[i] = action.target;
      values[i] = action.value;
      signatures[i] = action.signature;
      calldatas[i] = action.data;
    }

    bytes memory proposalCalldata = abi.encodeCall(
      IGovernorBravo.propose, (targets, values, signatures, calldatas, PROPOSAL_DESCRIPTION)
    );
    console2.log("GovernorBravo.propose() Calldata:");
    console2.logBytes(proposalCalldata);

    GOVERNOR_BRAVO.propose(targets, values, signatures, calldatas, PROPOSAL_DESCRIPTION);
    vm.stopBroadcast();
  }
}

interface IGovernorBravo {
  function propose(
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory description
  ) external returns (uint256);
}
