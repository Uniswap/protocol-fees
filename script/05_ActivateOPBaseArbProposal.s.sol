// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";

interface IL1CrossDomainMessenger {
  function sendMessage(address _target, bytes memory _message, uint32 _minGasLimit) external payable;
}

interface IInbox {
  function createRetryableTicket(
    address to,
    uint256 l2CallValue,
    uint256 maxSubmissionCost,
    address excessFeeRefundAddress,
    address callValueRefundAddress,
    uint256 gasLimit,
    uint256 maxFeePerGas,
    bytes calldata data
  ) external payable returns (uint256);
}

interface ICrossChainAccount {
  function forward(address target, bytes memory data) external;
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

struct ProposalAction {
  address target;
  uint256 value;
  string signature;
  bytes data;
}

/// @title ActivateOPBaseArbProposal
/// @notice Governance proposal to activate V3 protocol fees on OP Mainnet, Base, and Arbitrum
/// @dev This proposal transfers v3 factory ownership to the pre-deployed V3OpenFeeAdapter
///      on each chain:
///      - OP Mainnet & Base: L1CrossDomainMessenger → CrossChainAccount → factory.setOwner()
///      - Arbitrum: Inbox.createRetryableTicket() → factory.setOwner() (aliased Timelock is owner)
///
///      Prerequisites (must be completed before proposal execution):
///      1. V3OpenFeeAdapter must be deployed on all 3 chains
///      2. V3OpenFeeAdapter owner and feeSetter must be set to the respective governance controller
///      3. Fee tier defaults must be configured on V3OpenFeeAdapter
///
///      Post-execution state:
///      - factory.owner() = V3OpenFeeAdapter (all chains)
///      - OP/Base: V3OpenFeeAdapter.owner() = CrossChainAccount (via L1 Timelock + XDM)
///      - Arbitrum: V3OpenFeeAdapter.owner() = aliased Timelock (via retryable tickets)
contract ActivateOPBaseArbProposal is Script {
  IGovernorBravo internal constant GOVERNOR_BRAVO =
    IGovernorBravo(0x408ED6354d4973f66138C91495F2f2FCbd8724C3);

  // Gas limits
  uint32 internal constant XDM_GAS_LIMIT = 200_000;
  uint256 internal constant ARB_GAS_LIMIT = 200_000;
  uint256 internal constant ARB_MAX_FEE_PER_GAS = 0.1 gwei;
  uint256 internal constant ARB_MAX_SUBMISSION_COST = 0.01 ether;

  // ─── OP Mainnet ───

  IL1CrossDomainMessenger internal constant OP_L1_MESSENGER =
    IL1CrossDomainMessenger(0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1);

  address internal constant OP_CROSS_CHAIN_ACCOUNT = 0xa1dD330d602c32622AA270Ea73d078B803Cb3518;
  address internal constant OP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

  /// @dev Set after V3OpenFeeAdapter is deployed on OP Mainnet
  address internal constant OP_FEE_ADAPTER = address(0); // TODO: fill after deployment

  // ─── Base ────

  IL1CrossDomainMessenger internal constant BASE_L1_MESSENGER =
    IL1CrossDomainMessenger(0x866E82a600A1414e583f7F13623F1aC5d58b0Afa);

  address internal constant BASE_CROSS_CHAIN_ACCOUNT = 0x31FAfd4889FA1269F7a13A66eE0fB458f27D72A9;
  address internal constant BASE_V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;

  /// @dev Set after V3OpenFeeAdapter is deployed on Base
  address internal constant BASE_FEE_ADAPTER = address(0); // TODO: fill after deployment

  // ─── Arbitrum ───

  /// @dev Arbitrum One Inbox on L1
  IInbox internal constant ARB_INBOX = IInbox(0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f);

  address internal constant ARB_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

  /// @dev Aliased L1 Timelock on Arbitrum (used as refund address for excess retryable ticket ETH)
  address internal constant ARB_ALIASED_TIMELOCK = 0x2BAD8182C09F50c8318d769245beA52C32Be46CD;

  /// @dev Set after V3OpenFeeAdapter is deployed on Arbitrum
  address internal constant ARB_FEE_ADAPTER = address(0); // TODO: fill after deployment

  // ─── Proposal ───

  string internal constant PROPOSAL_DESCRIPTION =
    "# Activate V3 Protocol Fees on OP Mainnet, Base, and Arbitrum\n\n"
    "This proposal activates Uniswap V3 protocol fees on OP Mainnet, Base, and Arbitrum by\n"
    "transferring V3 factory ownership on each chain to a pre-deployed V3OpenFeeAdapter.\n\n"
    "## Actions\n\n"
    "**OP Mainnet & Base:** Sends cross-domain messages via L1CrossDomainMessenger to the\n"
    "existing CrossChainAccount on L2, which forwards the call to transfer V3 factory ownership.\n\n"
    "**Arbitrum:** Sends a retryable ticket via the Arbitrum Inbox. The L1 Timelock's aliased\n"
    "address is the current factory owner on Arbitrum, so the retryable ticket directly calls\n"
    "factory.setOwner(adapter).\n\n"
    "## Fee Configuration\n\n"
    "The V3OpenFeeAdapter on each chain is pre-configured with the same fee tier defaults as\n"
    "Ethereum mainnet:\n"
    "- 0.01% and 0.05% tiers: protocol fee = 1/4th of LP fees\n"
    "- 0.30% and 1.00% tiers: protocol fee = 1/6th of LP fees\n\n"
    "## Post-execution\n\n"
    "- V3 factory ownership is transferred to V3OpenFeeAdapter (all chains)\n"
    "- OP/Base: V3OpenFeeAdapter controlled by CrossChainAccount (via L1 Timelock + XDM)\n"
    "- Arbitrum: V3OpenFeeAdapter controlled by aliased Timelock (via retryable tickets)\n"
    "- Anyone can trigger fee updates permissionlessly via V3OpenFeeAdapter\n"
    "- Fee parameters can be adjusted by governance\n";

  function setUp() public {}

  /// @notice Build the proposal actions
  function _buildActions() internal pure returns (ProposalAction[] memory actions) {
    require(OP_FEE_ADAPTER != address(0), "OP fee adapter address not set");
    require(BASE_FEE_ADAPTER != address(0), "Base fee adapter address not set");
    require(ARB_FEE_ADAPTER != address(0), "Arbitrum fee adapter address not set");

    actions = new ProposalAction[](3);

    // Action 0: Transfer OP Mainnet V3 factory ownership to V3OpenFeeAdapter
    // L1 Timelock → L1CrossDomainMessenger(OP) → CrossChainAccount.forward(factory,
    // setOwner(adapter))
    actions[0] = ProposalAction({
      target: address(OP_L1_MESSENGER),
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IL1CrossDomainMessenger.sendMessage,
        (
          OP_CROSS_CHAIN_ACCOUNT,
          abi.encodeCall(
            ICrossChainAccount.forward,
            (OP_V3_FACTORY, abi.encodeCall(IUniswapV3Factory.setOwner, (OP_FEE_ADAPTER)))
          ),
          XDM_GAS_LIMIT
        )
      )
    });

    // Action 1: Transfer Base V3 factory ownership to V3OpenFeeAdapter
    // L1 Timelock → L1CrossDomainMessenger(Base) → CrossChainAccount.forward(factory,
    // setOwner(adapter))
    actions[1] = ProposalAction({
      target: address(BASE_L1_MESSENGER),
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IL1CrossDomainMessenger.sendMessage,
        (
          BASE_CROSS_CHAIN_ACCOUNT,
          abi.encodeCall(
            ICrossChainAccount.forward,
            (BASE_V3_FACTORY, abi.encodeCall(IUniswapV3Factory.setOwner, (BASE_FEE_ADAPTER)))
          ),
          XDM_GAS_LIMIT
        )
      )
    });

    // Action 2: Transfer Arbitrum V3 factory ownership to V3OpenFeeAdapter
    // L1 Timelock → Inbox.createRetryableTicket() → factory.setOwner(adapter)
    // msg.sender on L2 = aliased Timelock = current factory owner
    actions[2] = ProposalAction({
      target: address(ARB_INBOX),
      value: ARB_MAX_SUBMISSION_COST + ARB_GAS_LIMIT * ARB_MAX_FEE_PER_GAS,
      signature: "",
      data: abi.encodeCall(
        IInbox.createRetryableTicket,
        (
          ARB_V3_FACTORY,
          0, // l2CallValue
          ARB_MAX_SUBMISSION_COST,
          ARB_ALIASED_TIMELOCK, // excessFeeRefundAddress
          ARB_ALIASED_TIMELOCK, // callValueRefundAddress
          ARB_GAS_LIMIT,
          ARB_MAX_FEE_PER_GAS,
          abi.encodeCall(IUniswapV3Factory.setOwner, (ARB_FEE_ADAPTER))
        )
      )
    });
  }

  /// @notice Submit the proposal to GovernorBravo
  function run() public {
    vm.startBroadcast();

    ProposalAction[] memory actions = _buildActions();

    address[] memory targets = new address[](actions.length);
    uint256[] memory values = new uint256[](actions.length);
    string[] memory signatures = new string[](actions.length);
    bytes[] memory calldatas = new bytes[](actions.length);

    for (uint256 i = 0; i < actions.length; i++) {
      targets[i] = actions[i].target;
      values[i] = actions[i].value;
      signatures[i] = actions[i].signature;
      calldatas[i] = actions[i].data;
    }

    console2.log("=== Proposal: Activate V3 Fees on OP + Base + Arbitrum ===");
    for (uint256 i = 0; i < actions.length; i++) {
      console2.log("Action", i);
      console2.log("  Target:", actions[i].target);
      console2.logBytes(actions[i].data);
    }

    GOVERNOR_BRAVO.propose(targets, values, signatures, calldatas, PROPOSAL_DESCRIPTION);

    vm.stopBroadcast();
  }

  /// @notice Execute actions directly (for testing with prank)
  function runPranked(address executor) public {
    vm.startPrank(executor);

    ProposalAction[] memory actions = _buildActions();
    for (uint256 i = 0; i < actions.length; i++) {
      (bool success,) = actions[i].target.call{value: actions[i].value}(actions[i].data);
      require(success, "Action failed");
    }

    vm.stopPrank();
  }
}
