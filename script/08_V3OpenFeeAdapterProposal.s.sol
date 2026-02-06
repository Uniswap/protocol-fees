// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {IV3FeeAdapter} from "../src/interfaces/IV3FeeAdapter.sol";
import {IV3OpenFeeAdapter} from "../src/interfaces/IV3OpenFeeAdapter.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";

struct ProposalAction {
  address target;
  uint256 value;
  string signature;
  bytes data;
}

/// @title V3OpenFeeAdapterProposal
/// @notice Governance proposal to switch from V3FeeAdapter to V3OpenFeeAdapter
/// @dev This proposal transfers V3 factory ownership from the current V3FeeAdapter
///      to the new V3OpenFeeAdapter, enabling permissionless fee updates with
///      waterfall resolution (pool override → tier default → global default)
contract V3OpenFeeAdapterProposal is Script, StdAssertions {
  string internal constant PROPOSAL_DESCRIPTION = "# V3 Open Fee Adapter Migration\n\n"
    "This proposal migrates the Uniswap V3 fee adapter from the current merkle-proof based "
    "`V3FeeAdapter` to the new permissionless `V3OpenFeeAdapter`.\n\n" "## Summary\n\n"
    "The new V3OpenFeeAdapter introduces:\n"
    "- **Permissionless fee updates**: Anyone can trigger fee updates without merkle proofs\n"
    "- **Waterfall fee resolution**: Pool override -> Tier default -> Global default\n"
    "- **Explicit zero fees**: Ability to disable fees for specific pools or tiers\n"
    "- **Simplified governance**: No need to update merkle roots for new pools\n\n"
    "## Proposal Actions\n\n"
    "1. Transfer V3 factory ownership from V3FeeAdapter to V3OpenFeeAdapter\n\n" "```solidity\n"
    "V3FeeAdapter.setFactoryOwner(address(V3OpenFeeAdapter));\n" "```\n\n"
    "## Fee Configuration\n\n" "The new adapter is pre-configured with the same fee tiers:\n"
    "- 0.01% tier: 1/4 protocol fee\n" "- 0.05% tier: 1/4 protocol fee\n"
    "- 0.30% tier: 1/6 protocol fee\n" "- 1.00% tier: 1/6 protocol fee\n\n" "## Security\n\n"
    "- V3OpenFeeAdapter ownership is held by the UNI Timelock\n"
    "- Fee setter role is held by the UNI Timelock\n"
    "- All existing pool fees remain unchanged until explicitly updated\n";

  /// @notice The V3 Factory contract
  IUniswapV3Factory public constant V3_FACTORY =
    IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

  /// @notice The UNI Timelock
  address public constant TIMELOCK = 0x1a9C8182C09F50C8318d769245beA52c32BE35BC;

  /// @notice Executes proposal actions via vm.prank (for testing)
  /// @dev Simulates governance execution of the proposal
  /// @param v3FeeAdapter The current V3FeeAdapter that owns the factory
  /// @param v3OpenFeeAdapter The new V3OpenFeeAdapter to transfer ownership to
  function runPranked(IV3FeeAdapter v3FeeAdapter, IV3OpenFeeAdapter v3OpenFeeAdapter) public {
    vm.startPrank(TIMELOCK);
    ProposalAction[] memory actions = _run(v3FeeAdapter, v3OpenFeeAdapter);
    for (uint256 i = 0; i < actions.length; i++) {
      ProposalAction memory action = actions[i];
      (bool success,) = action.target.call{value: action.value}(action.data);
      require(success, "Proposal action failed");
    }
    vm.stopPrank();
  }

  /// @notice Generates proposal actions for the V3OpenFeeAdapter migration
  /// @dev The V3OpenFeeAdapter must be deployed before this proposal is submitted
  /// @param v3FeeAdapter The current V3FeeAdapter that owns the factory
  /// @param v3OpenFeeAdapter The pre-deployed V3OpenFeeAdapter address
  /// @return actions Array of proposal actions to execute
  function _run(IV3FeeAdapter v3FeeAdapter, IV3OpenFeeAdapter v3OpenFeeAdapter)
    public
    view
    returns (ProposalAction[] memory actions)
  {
    // Verify V3OpenFeeAdapter is properly configured
    assertEq(address(v3OpenFeeAdapter.FACTORY()), address(V3_FACTORY), "Incorrect factory");
    require(
      v3OpenFeeAdapter.feeSetter() == TIMELOCK, "V3OpenFeeAdapter feeSetter not set to timelock"
    );

    // Verify V3FeeAdapter currently owns the factory
    assertEq(V3_FACTORY.owner(), address(v3FeeAdapter), "V3FeeAdapter must own factory");

    // Create proposal action
    actions = new ProposalAction[](1);

    // Transfer factory ownership from V3FeeAdapter to V3OpenFeeAdapter
    actions[0] = ProposalAction({
      target: address(v3FeeAdapter),
      value: 0,
      signature: "",
      data: abi.encodeCall(v3FeeAdapter.setFactoryOwner, (address(v3OpenFeeAdapter)))
    });

    return actions;
  }

  /// @notice Returns the proposal description
  function description() external pure returns (string memory) {
    return PROPOSAL_DESCRIPTION;
  }
}
