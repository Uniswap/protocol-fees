// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";

interface IL1CrossDomainMessenger {
  function sendMessage(address _target, bytes memory _message, uint32 _minGasLimit) external payable;
}

interface IOptimismPortal {
  function depositTransaction(
    address _to,
    uint256 _value,
    uint64 _gasLimit,
    bool _isCreation,
    bytes memory _data
  ) external payable;
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

/// @title ActivateL2sProposal
/// @notice Governance proposal to activate V3 protocol fees on Celo, Soneium, Worldchain,
///         XLayer, and Zora
/// @dev This proposal has two phases:
///
///      Phase 1 — Unify ownership model:
///      Transfers V3 factory ownership on Soneium and XLayer from the aliased Timelock
///      to V3OpenFeeAdapter via OptimismPortal.depositTransaction().
///      Transfers V3 factory ownership on Celo from the Wormhole Receiver
///      to V3OpenFeeAdapter via the Uniswap Wormhole Message Sender.
///
///      Phase 2 — Activate fees:
///      Transfers V3 factory ownership on Worldchain and Zora from their existing
///      CrossChainAccount to V3OpenFeeAdapter via L1CrossDomainMessenger -> XDM.
///
///      All actions must be ordered correctly: Phase 1 deposit transactions are processed
///      in the same L2 block, so ordering within the proposal matters.
///
///      Prerequisites (must be completed before proposal execution):
///      1. V3OpenFeeAdapter must be deployed on all 5 chains
///      2. CrossChainAccount must exist on all 5 chains (deployed by the deploy script)
///      3. V3OpenFeeAdapter owner and feeSetter must be set to the respective CrossChainAccount
///      4. Fee tier defaults must be configured on V3OpenFeeAdapter
///
///      Post-execution state on each chain:
///      - factory.owner() = V3OpenFeeAdapter
///      - V3OpenFeeAdapter.owner() = CrossChainAccount (controlled by L1 Timelock via XDM)
///      - V3OpenFeeAdapter.feeSetter() = CrossChainAccount
contract ActivateL2sProposal is Script {
  IGovernorBravo internal constant GOVERNOR_BRAVO =
    IGovernorBravo(0x408ED6354d4973f66138C91495F2f2FCbd8724C3);

  // Gas limits
  uint32 internal constant XDM_GAS_LIMIT = 200_000;
  uint64 internal constant DEPOSIT_GAS_LIMIT = 200_000;

  // ─── Wormhole ───

  /// @dev Uniswap Wormhole Message Sender on L1 (owned by L1 Timelock)
  IWormholeSender internal constant WORMHOLE_SENDER =
    IWormholeSender(0xf5F4496219F31CDCBa6130B5402873624585615a);

  /// @dev Wormhole Core Bridge on Ethereum mainnet
  address internal constant WORMHOLE_BRIDGE = 0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B;

  /// @dev Wormhole chain ID for Celo
  uint16 internal constant WORMHOLE_CELO_CHAIN_ID = 14;

  // ─── Soneium (owner = aliased Timelock -> depositTransaction) ───

  IOptimismPortal internal constant SONEIUM_PORTAL =
    IOptimismPortal(0x88e529A6ccd302c948689Cd5156C83D4614FAE92);

  address internal constant SONEIUM_V3_FACTORY = 0x42aE7Ec7ff020412639d443E245D936429Fbe717;

  /// @dev Set after V3OpenFeeAdapter is deployed on Soneium
  address internal constant SONEIUM_FEE_ADAPTER = address(0); // TODO: fill after deployment

  // ─── XLayer (owner = aliased Timelock -> depositTransaction) ───

  IOptimismPortal internal constant XLAYER_PORTAL =
    IOptimismPortal(0x64057ad1DdAc804d0D26A7275b193D9DACa19993);

  address internal constant XLAYER_V3_FACTORY = 0x4B2ab38DBF28D31D467aA8993f6c2585981D6804;

  /// @dev Set after V3OpenFeeAdapter is deployed on XLayer
  address internal constant XLAYER_FEE_ADAPTER = address(0); // TODO: fill after deployment

  // ─── Celo (owner = Wormhole Receiver -> Wormhole message) ───

  address internal constant CELO_V3_FACTORY = 0xAfE208a311B21f13EF87E33A90049fC17A7acDEc;

  /// @dev Set after V3OpenFeeAdapter is deployed on Celo
  address internal constant CELO_FEE_ADAPTER = address(0); // TODO: fill after deployment

  // ─── Worldchain (owner = CrossChainAccount -> XDM) ───

  IL1CrossDomainMessenger internal constant WORLDCHAIN_L1_MESSENGER =
    IL1CrossDomainMessenger(0xf931a81D18B1766d15695ffc7c1920a62b7e710a);

  address internal constant WORLDCHAIN_CROSS_CHAIN_ACCOUNT =
    0xcb2436774C3e191c85056d248EF4260ce5f27A9D;

  address internal constant WORLDCHAIN_V3_FACTORY = 0x7a5028BDa40e7B173C278C5342087826455ea25a;

  /// @dev Set after V3OpenFeeAdapter is deployed on Worldchain
  address internal constant WORLDCHAIN_FEE_ADAPTER = address(0); // TODO: fill after deployment

  // ─── Zora (owner = CrossChainAccount -> XDM) ───

  IL1CrossDomainMessenger internal constant ZORA_L1_MESSENGER =
    IL1CrossDomainMessenger(0xdC40a14d9abd6F410226f1E6de71aE03441ca506);

  address internal constant ZORA_CROSS_CHAIN_ACCOUNT = 0x36eEC182D0B24Df3DC23115D64DB521A93D5154f;

  address internal constant ZORA_V3_FACTORY = 0x7145F8aeef1f6510E92164038E1B6F8cB2c42Cbb;

  /// @dev Set after V3OpenFeeAdapter is deployed on Zora
  address internal constant ZORA_FEE_ADAPTER = address(0); // TODO: fill after deployment

  // ─── Proposal ───

  string internal constant PROPOSAL_DESCRIPTION = "# Activate V3 Protocol Fees on Celo, Soneium, Worldchain, X Layer, and Zora\n\n"
    "This proposal activates Uniswap V3 protocol fees on five L2 chains by transferring\n"
    "V3 factory ownership to pre-deployed V3OpenFeeAdapter contracts.\n\n"
    "## Phase 1: Unify Ownership Model\n\n"
    "For **Soneium** and **X Layer**, the V3 factory is currently owned by the aliased L1\n"
    "Timelock (via depositTransaction). This proposal transfers ownership directly to the\n"
    "V3OpenFeeAdapter via OptimismPortal.depositTransaction().\n\n"
    "For **Celo**, the V3 factory is owned by a Uniswap Wormhole Message Receiver (pre-OP\n"
    "Stack governance). This proposal sends a final Wormhole message to transfer ownership\n"
    "to the V3OpenFeeAdapter.\n\n" "## Phase 2: Activate via XDM\n\n"
    "For **Worldchain** and **Zora**, the V3 factory is already owned by a CrossChainAccount.\n"
    "This proposal sends L1CrossDomainMessenger messages to transfer ownership to the\n"
    "V3OpenFeeAdapter.\n\n" "## Fee Configuration\n\n"
    "The V3OpenFeeAdapter on each chain is pre-configured with the same fee tier defaults as\n"
    "Ethereum mainnet:\n" "- 0.01% and 0.05% tiers: protocol fee = 1/4th of LP fees\n"
    "- 0.30% and 1.00% tiers: protocol fee = 1/6th of LP fees\n\n" "## Post-execution\n\n"
    "After this proposal, all chains will have a unified ownership model:\n"
    "- V3 factory -> owned by V3OpenFeeAdapter\n"
    "- V3OpenFeeAdapter -> owned by CrossChainAccount\n"
    "- CrossChainAccount -> controlled by L1 Timelock via L2CrossDomainMessenger\n"
    "- Fee parameters adjustable by governance via CrossChainAccount\n";

  function setUp() public {}

  /// @notice Build the proposal actions
  function _buildActions() internal pure returns (ProposalAction[] memory actions) {
    require(SONEIUM_FEE_ADAPTER != address(0), "Soneium fee adapter address not set");
    require(XLAYER_FEE_ADAPTER != address(0), "XLayer fee adapter address not set");
    require(CELO_FEE_ADAPTER != address(0), "Celo fee adapter address not set");
    require(WORLDCHAIN_FEE_ADAPTER != address(0), "Worldchain fee adapter address not set");
    require(ZORA_FEE_ADAPTER != address(0), "Zora fee adapter address not set");

    actions = new ProposalAction[](5);

    // ═══ Phase 1: Unify ownership ═══

    // Action 0: Soneium — depositTransaction to transfer factory to fee adapter
    // L1 Timelock -> OptimismPortal(Soneium) -> factory.setOwner(feeAdapter)
    // msg.sender on L2 = aliased Timelock = current factory owner
    actions[0] = ProposalAction({
      target: address(SONEIUM_PORTAL),
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IOptimismPortal.depositTransaction,
        (
          SONEIUM_V3_FACTORY,
          0,
          DEPOSIT_GAS_LIMIT,
          false,
          abi.encodeCall(IUniswapV3Factory.setOwner, (SONEIUM_FEE_ADAPTER))
        )
      )
    });

    // Action 1: XLayer — depositTransaction to transfer factory to fee adapter
    // L1 Timelock -> OptimismPortal(XLayer) -> factory.setOwner(feeAdapter)
    // msg.sender on L2 = aliased Timelock = current factory owner
    actions[1] = ProposalAction({
      target: address(XLAYER_PORTAL),
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IOptimismPortal.depositTransaction,
        (
          XLAYER_V3_FACTORY,
          0,
          DEPOSIT_GAS_LIMIT,
          false,
          abi.encodeCall(IUniswapV3Factory.setOwner, (XLAYER_FEE_ADAPTER))
        )
      )
    });

    // Action 2: Celo — Wormhole message to transfer factory to fee adapter
    // L1 Timelock -> WormholeSender -> Wormhole -> Celo WormholeReceiver -> factory.setOwner()
    {
      address[] memory targets = new address[](1);
      uint256[] memory values = new uint256[](1);
      bytes[] memory datas = new bytes[](1);

      targets[0] = CELO_V3_FACTORY;
      values[0] = 0;
      datas[0] = abi.encodeCall(IUniswapV3Factory.setOwner, (CELO_FEE_ADAPTER));

      actions[2] = ProposalAction({
        target: address(WORMHOLE_SENDER),
        value: 0, // TODO: verify wormhole fee
        signature: "",
        data: abi.encodeCall(
          IWormholeSender.sendMessage,
          (targets, values, datas, WORMHOLE_BRIDGE, WORMHOLE_CELO_CHAIN_ID)
        )
      });
    }

    // ═══ Phase 2: Activate via XDM ═══

    // Action 3: Worldchain — XDM to transfer factory to fee adapter
    // L1 Timelock -> L1CrossDomainMessenger -> CrossChainAccount.forward(factory, setOwner)
    actions[3] = ProposalAction({
      target: address(WORLDCHAIN_L1_MESSENGER),
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IL1CrossDomainMessenger.sendMessage,
        (
          WORLDCHAIN_CROSS_CHAIN_ACCOUNT,
          abi.encodeCall(
            ICrossChainAccount.forward,
            (
              WORLDCHAIN_V3_FACTORY,
              abi.encodeCall(IUniswapV3Factory.setOwner, (WORLDCHAIN_FEE_ADAPTER))
            )
          ),
          XDM_GAS_LIMIT
        )
      )
    });

    // Action 4: Zora — XDM to transfer factory to fee adapter
    // L1 Timelock -> L1CrossDomainMessenger -> CrossChainAccount.forward(factory, setOwner)
    actions[4] = ProposalAction({
      target: address(ZORA_L1_MESSENGER),
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IL1CrossDomainMessenger.sendMessage,
        (
          ZORA_CROSS_CHAIN_ACCOUNT,
          abi.encodeCall(
            ICrossChainAccount.forward,
            (ZORA_V3_FACTORY, abi.encodeCall(IUniswapV3Factory.setOwner, (ZORA_FEE_ADAPTER)))
          ),
          XDM_GAS_LIMIT
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

    console2.log("=== Proposal: Activate V3 Fees on L2s ===");
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
