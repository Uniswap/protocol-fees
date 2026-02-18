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

interface IWormholeSender {
  function sendMessage(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory datas,
    address wormhole,
    uint16 chainId
  ) external;
}

interface IUniswapV2Factory {
  function setFeeTo(address) external;
}

interface IV3FeeAdapter {
  function setFactoryOwner(address newOwner) external;
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
/// @notice Governance proposal to activate protocol fees on OP Mainnet, Base, Arbitrum, and
///         Ethereum mainnet, plus Celo governance handoff
/// @dev This proposal performs four categories of actions:
///
///      1. L2 V3 factory activation — transfer ownership to V3OpenFeeAdapter:
///         - OP Mainnet & Base: L1CrossDomainMessenger → CrossChainAccount → factory.setOwner()
///         - Arbitrum: Inbox.createRetryableTicket() → factory.setOwner()
///
///      2. Mainnet V3 factory migration — transfer from V3FeeAdapter to V3OpenFeeAdapter:
///         - V3FeeAdapter.setFactoryOwner(V3OpenFeeAdapter) (direct L1 call)
///
///      3. L2 V2 fee activation — set feeTo to TokenJar:
///         - OP Mainnet & Base: L1CrossDomainMessenger → CrossChainAccount →
/// V2Factory.setFeeTo()
///         - Arbitrum: Inbox.createRetryableTicket() → V2Factory.setFeeTo()
///
///      4. Celo governance handoff — Wormhole → CrossChainAccount:
///         - WormholeSender → Celo WormholeReceiver → factory.setOwner(CrossChainAccount)
///
///      Prerequisites (must be completed before proposal execution):
///      1. V3OpenFeeAdapter and TokenJar must be deployed on OP, Base, and Arbitrum
///      2. V3OpenMainnetDeployer must be deployed on Ethereum mainnet
///      3. Fee tier defaults must be configured on all V3OpenFeeAdapters
///      4. CrossChainAccount must be deployed on Celo (by the DeployCelo script)
///
///      Post-execution state:
///      - V3 factory.owner() = V3OpenFeeAdapter (OP, Base, Arbitrum, mainnet)
///      - V2 factory.feeTo() = TokenJar (OP, Base, Arbitrum)
///      - OP/Base: governance via CrossChainAccount (L1 Timelock + XDM)
///      - Arbitrum: governance via aliased Timelock (retryable tickets)
///      - Celo: V3 factory.owner() = CrossChainAccount (ready for proposal 06)
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

  address internal constant OP_V2_FACTORY = 0x0c3c1c532F1e39EdF36BE9Fe0bE1410313E074Bf;

  /// @dev Set after TokenJar is deployed on OP Mainnet
  address internal constant OP_TOKEN_JAR = address(0); // TODO: fill after deployment

  // ─── Base ────

  IL1CrossDomainMessenger internal constant BASE_L1_MESSENGER =
    IL1CrossDomainMessenger(0x866E82a600A1414e583f7F13623F1aC5d58b0Afa);

  address internal constant BASE_CROSS_CHAIN_ACCOUNT = 0x31FAfd4889FA1269F7a13A66eE0fB458f27D72A9;
  address internal constant BASE_V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;

  /// @dev Set after V3OpenFeeAdapter is deployed on Base
  address internal constant BASE_FEE_ADAPTER = address(0); // TODO: fill after deployment

  address internal constant BASE_V2_FACTORY = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;

  /// @dev Set after TokenJar is deployed on Base
  address internal constant BASE_TOKEN_JAR = address(0); // TODO: fill after deployment

  // ─── Arbitrum ───

  /// @dev Arbitrum One Inbox on L1
  IInbox internal constant ARB_INBOX = IInbox(0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f);

  address internal constant ARB_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

  /// @dev Aliased L1 Timelock on Arbitrum (used as refund address for excess retryable ticket ETH)
  address internal constant ARB_ALIASED_TIMELOCK = 0x2BAD8182C09F50c8318d769245beA52C32Be46CD;

  /// @dev Set after V3OpenFeeAdapter is deployed on Arbitrum
  address internal constant ARB_FEE_ADAPTER = address(0); // TODO: fill after deployment

  address internal constant ARB_V2_FACTORY = 0xf1D7CC64Fb4452F05c498126312eBE29f30Fbcf9;

  /// @dev Set after TokenJar is deployed on Arbitrum
  address internal constant ARB_TOKEN_JAR = address(0); // TODO: fill after deployment

  // ─── Ethereum Mainnet (V3 factory migration: V3FeeAdapter → V3OpenFeeAdapter) ───

  /// @dev Current V3FeeAdapter (merkle-based) — owns the mainnet V3 factory since proposal 04
  /// Set after V3FeeAdapter address is confirmed from MainnetDeployer
  address internal constant MAINNET_V3_FEE_ADAPTER = address(0); // TODO: fill with deployed address

  /// @dev New V3OpenFeeAdapter (permissionless) — deployed by V3OpenMainnetDeployer
  address internal constant MAINNET_V3_OPEN_FEE_ADAPTER = address(0); // TODO: fill after deployment

  // ─── Celo (Wormhole handoff: Wormhole Receiver → CrossChainAccount) ───

  /// @dev Uniswap Wormhole Message Sender on L1 (owned by L1 Timelock)
  IWormholeSender internal constant WORMHOLE_SENDER =
    IWormholeSender(0xf5F4496219F31CDCBa6130B5402873624585615a);

  /// @dev Wormhole Core Bridge on Ethereum mainnet
  address internal constant WORMHOLE_BRIDGE = 0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B;

  /// @dev Wormhole chain ID for Celo
  uint16 internal constant WORMHOLE_CELO_CHAIN_ID = 14;

  address internal constant CELO_V3_FACTORY = 0xAfE208a311B21f13EF87E33A90049fC17A7acDEc;

  /// @dev Set after CrossChainAccount is deployed on Celo (by DeployCelo script)
  address internal constant CELO_CROSS_CHAIN_ACCOUNT = address(0); // TODO: fill after deployment

  // ─── Proposal ───

  string internal constant PROPOSAL_DESCRIPTION = "# Activate Protocol Fees on OP Mainnet, Base, Arbitrum, and Ethereum + Celo Governance Handoff\n\n"
    "This proposal activates Uniswap protocol fees across OP Mainnet, Base, Arbitrum, and Ethereum\n"
    "mainnet, and prepares Celo for fee activation in a follow-up proposal.\n\n"
    "## V3 Factory Activation (L2)\n\n"
    "**OP Mainnet & Base:** Sends cross-domain messages via L1CrossDomainMessenger to the\n"
    "existing CrossChainAccount on L2, which forwards the call to transfer V3 factory ownership\n"
    "to V3OpenFeeAdapter.\n\n"
    "**Arbitrum:** Sends a retryable ticket via the Arbitrum Inbox. The L1 Timelock's aliased\n"
    "address is the current factory owner on Arbitrum, so the retryable ticket directly calls\n"
    "factory.setOwner(adapter).\n\n" "## V3 Factory Migration (Mainnet)\n\n"
    "Transfers mainnet V3 factory ownership from the merkle-based V3FeeAdapter to the new\n"
    "permissionless V3OpenFeeAdapter via V3FeeAdapter.setFactoryOwner().\n\n"
    "## V2 Fee Activation (L2)\n\n"
    "Sets V2 factory feeTo to the pre-deployed TokenJar on OP Mainnet, Base, and Arbitrum,\n"
    "enabling V2 protocol fee collection.\n\n" "## Celo Governance Handoff\n\n"
    "Sends a final Wormhole message to transfer the Celo V3 factory from the Wormhole Receiver\n"
    "to the CrossChainAccount deployed via the OP bridge. This unifies Celo under the same OP\n"
    "Stack governance model used by other chains.\n\n" "## Fee Configuration\n\n"
    "The V3OpenFeeAdapter on each chain is pre-configured with the same fee tier defaults as\n"
    "Ethereum mainnet:\n" "- 0.01% and 0.05% tiers: protocol fee = 1/4th of LP fees\n"
    "- 0.30% and 1.00% tiers: protocol fee = 1/6th of LP fees\n\n" "## Post-execution\n\n"
    "- V3 factory.owner() = V3OpenFeeAdapter (OP, Base, Arbitrum, mainnet)\n"
    "- V2 factory.feeTo() = TokenJar (OP, Base, Arbitrum)\n"
    "- OP/Base: governance via CrossChainAccount (L1 Timelock + XDM)\n"
    "- Arbitrum: governance via aliased Timelock (retryable tickets)\n"
    "- Celo: V3 factory ownership transferred to CrossChainAccount (fee activation in follow-up)\n"
    "- Anyone can trigger fee updates permissionlessly via V3OpenFeeAdapter\n"
    "- Fee parameters can be adjusted by governance\n";

  function setUp() public {}

  /// @notice Build the proposal actions
  function _buildActions() internal pure returns (ProposalAction[] memory actions) {
    require(OP_FEE_ADAPTER != address(0), "OP fee adapter address not set");
    require(OP_TOKEN_JAR != address(0), "OP TokenJar address not set");
    require(BASE_FEE_ADAPTER != address(0), "Base fee adapter address not set");
    require(BASE_TOKEN_JAR != address(0), "Base TokenJar address not set");
    require(ARB_FEE_ADAPTER != address(0), "Arbitrum fee adapter address not set");
    require(ARB_TOKEN_JAR != address(0), "Arbitrum TokenJar address not set");
    require(MAINNET_V3_FEE_ADAPTER != address(0), "Mainnet V3FeeAdapter address not set");
    require(MAINNET_V3_OPEN_FEE_ADAPTER != address(0), "Mainnet V3OpenFeeAdapter address not set");
    require(CELO_CROSS_CHAIN_ACCOUNT != address(0), "Celo CrossChainAccount address not set");

    actions = new ProposalAction[](8);

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

    // Action 3: Mainnet — migrate V3 factory from V3FeeAdapter to V3OpenFeeAdapter
    // L1 Timelock → V3FeeAdapter.setFactoryOwner(V3OpenFeeAdapter)
    actions[3] = ProposalAction({
      target: MAINNET_V3_FEE_ADAPTER,
      value: 0,
      signature: "",
      data: abi.encodeCall(IV3FeeAdapter.setFactoryOwner, (MAINNET_V3_OPEN_FEE_ADAPTER))
    });

    // ═══ V2 Fee Activation ═══

    // Action 4: OP Mainnet — set V2 factory feeTo to TokenJar
    // L1 Timelock → L1CrossDomainMessenger(OP) → CrossChainAccount.forward(V2Factory, setFeeTo)
    actions[4] = ProposalAction({
      target: address(OP_L1_MESSENGER),
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IL1CrossDomainMessenger.sendMessage,
        (
          OP_CROSS_CHAIN_ACCOUNT,
          abi.encodeCall(
            ICrossChainAccount.forward,
            (OP_V2_FACTORY, abi.encodeCall(IUniswapV2Factory.setFeeTo, (OP_TOKEN_JAR)))
          ),
          XDM_GAS_LIMIT
        )
      )
    });

    // Action 5: Base — set V2 factory feeTo to TokenJar
    // L1 Timelock → L1CrossDomainMessenger(Base) → CrossChainAccount.forward(V2Factory,
    // setFeeTo)
    actions[5] = ProposalAction({
      target: address(BASE_L1_MESSENGER),
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IL1CrossDomainMessenger.sendMessage,
        (
          BASE_CROSS_CHAIN_ACCOUNT,
          abi.encodeCall(
            ICrossChainAccount.forward,
            (BASE_V2_FACTORY, abi.encodeCall(IUniswapV2Factory.setFeeTo, (BASE_TOKEN_JAR)))
          ),
          XDM_GAS_LIMIT
        )
      )
    });

    // Action 6: Arbitrum — set V2 factory feeTo to TokenJar
    // L1 Timelock → Inbox.createRetryableTicket() → V2Factory.setFeeTo(tokenJar)
    // msg.sender on L2 = aliased Timelock = current V2 feeToSetter
    actions[6] = ProposalAction({
      target: address(ARB_INBOX),
      value: ARB_MAX_SUBMISSION_COST + ARB_GAS_LIMIT * ARB_MAX_FEE_PER_GAS,
      signature: "",
      data: abi.encodeCall(
        IInbox.createRetryableTicket,
        (
          ARB_V2_FACTORY,
          0, // l2CallValue
          ARB_MAX_SUBMISSION_COST,
          ARB_ALIASED_TIMELOCK, // excessFeeRefundAddress
          ARB_ALIASED_TIMELOCK, // callValueRefundAddress
          ARB_GAS_LIMIT,
          ARB_MAX_FEE_PER_GAS,
          abi.encodeCall(IUniswapV2Factory.setFeeTo, (ARB_TOKEN_JAR))
        )
      )
    });

    // ═══ Celo Governance Handoff ═══

    // Action 7: Celo — Wormhole handoff: transfer factory from Wormhole Receiver →
    // CrossChainAccount L1 Timelock → WormholeSender → Wormhole → WormholeReceiver →
    // factory.setOwner()
    {
      address[] memory targets = new address[](1);
      uint256[] memory values = new uint256[](1);
      bytes[] memory datas = new bytes[](1);

      targets[0] = CELO_V3_FACTORY;
      values[0] = 0;
      datas[0] = abi.encodeCall(IUniswapV3Factory.setOwner, (CELO_CROSS_CHAIN_ACCOUNT));

      actions[7] = ProposalAction({
        target: address(WORMHOLE_SENDER),
        value: 0, // TODO: verify wormhole fee
        signature: "",
        data: abi.encodeCall(
          IWormholeSender.sendMessage,
          (targets, values, datas, WORMHOLE_BRIDGE, WORMHOLE_CELO_CHAIN_ID)
        )
      });
    }
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

    console2.log("=== Proposal: Activate V3 Fees on OP + Base + Arbitrum + Celo Handoff ===");
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
