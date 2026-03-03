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

interface IUniswapV2Factory {
  function setFeeTo(address) external;
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
/// @notice Governance proposal to activate V3 and V2 protocol fees on Celo, Soneium,
///         Worldchain, XLayer, and Zora
/// @dev This proposal has two phases:
///
///      Phase 1 — Activate via depositTransaction (aliased Timelock):
///      Soneium and XLayer: Transfers V3 factory ownership to V3OpenFeeAdapter and sets
///      V2 factory feeTo to TokenJar via OptimismPortal.depositTransaction().
///      msg.sender on L2 = aliased Timelock = current V3 factory owner + V2 feeToSetter.
///
///      Phase 2 — Activate via XDM (CrossChainAccount):
///      Celo, Worldchain, and Zora: Transfers V3 factory ownership to V3OpenFeeAdapter and
///      sets V2 factory feeTo to TokenJar via L1CrossDomainMessenger -> CrossChainAccount.
///      (Celo's CrossChainAccount received V3/V2 control from the Wormhole Receiver in the
///      previous proposal. Zora's V2 feeToSetter is transferred to the CrossChainAccount by
///      the Zora team prior to proposal execution.)
///
///      Prerequisites (must be completed before proposal execution):
///      1. V3OpenFeeAdapter and TokenJar must be deployed on all 5 chains
///      2. CrossChainAccount must exist on all 5 chains (deployed by the deploy script)
///      3. V3OpenFeeAdapter owner and feeSetter must be set to the respective CrossChainAccount
///      4. Fee tier defaults must be configured on V3OpenFeeAdapter
///      5. Previous proposal must have executed (Celo factory ownership transferred to
///         CrossChainAccount)
///      6. Zora V2 factory feeToSetter must be transferred to CrossChainAccount by the Zora team
///
///      Post-execution state on each chain:
///      - V3 factory.owner() = V3OpenFeeAdapter
///      - V2 factory.feeTo() = TokenJar
///      - V3OpenFeeAdapter.owner() = CrossChainAccount (controlled by L1 Timelock via XDM)
///      - V3OpenFeeAdapter.feeSetter() = CrossChainAccount
contract ActivateL2sProposal is Script {
  IGovernorBravo internal constant GOVERNOR_BRAVO =
    IGovernorBravo(0x408ED6354d4973f66138C91495F2f2FCbd8724C3);

  // Gas limits
  uint32 internal constant XDM_GAS_LIMIT = 200_000;
  uint64 internal constant DEPOSIT_GAS_LIMIT = 200_000;

  // ─── Soneium (owner = aliased Timelock -> depositTransaction) ───

  IOptimismPortal internal constant SONEIUM_PORTAL =
    IOptimismPortal(0x88e529A6ccd302c948689Cd5156C83D4614FAE92);

  address internal constant SONEIUM_V3_FACTORY = 0x42aE7Ec7ff020412639d443E245D936429Fbe717;

  address internal constant SONEIUM_FEE_ADAPTER = 0x47Cf920815344Fd684A48BBEFcbfbed9C7AE09CF;

  address internal constant SONEIUM_V2_FACTORY = 0x97FeBbC2AdBD5644ba22736E962564B23F5828CE;

  address internal constant SONEIUM_TOKEN_JAR = 0x85aeb792b94a9d79741002FC871423Ec5dAD29e9;

  // ─── XLayer (owner = aliased Timelock -> depositTransaction) ───

  IOptimismPortal internal constant XLAYER_PORTAL =
    IOptimismPortal(0x64057ad1DdAc804d0D26A7275b193D9DACa19993);

  address internal constant XLAYER_V3_FACTORY = 0x4B2ab38DBF28D31D467aA8993f6c2585981D6804;

  address internal constant XLAYER_FEE_ADAPTER = 0x6A88EF2e6511CAFfE2D006e260e7A5d1E7D4d7D7;

  address internal constant XLAYER_V2_FACTORY = 0xDf38F24fE153761634Be942F9d859f3DBA857E95;

  address internal constant XLAYER_TOKEN_JAR = 0x8Dd8B6D56e4a4A158EDbBfE7f2f703B8FFC1a754;

  // ─── Celo (owner = CrossChainAccount after Wormhole handoff -> XDM) ───

  IL1CrossDomainMessenger internal constant CELO_L1_MESSENGER =
    IL1CrossDomainMessenger(0x1AC1181fc4e4F877963680587AEAa2C90D7EbB95);

  address internal constant CELO_CROSS_CHAIN_ACCOUNT = 0x044aAF330d7fD6AE683EEc5c1C1d1fFf5196B6b7;

  address internal constant CELO_V3_FACTORY = 0xAfE208a311B21f13EF87E33A90049fC17A7acDEc;
  address internal constant CELO_V2_FACTORY = 0x79a530c8e2fA8748B7B40dd3629C0520c2cCf03f;

  address internal constant CELO_FEE_ADAPTER = 0xB9952C01830306ea2fAAe1505f6539BD260Bfc48;

  address internal constant CELO_TOKEN_JAR = 0x190c22c5085640D1cB60CeC88a4F736Acb59bb6B;

  // ─── Worldchain (owner = CrossChainAccount -> XDM) ───

  IL1CrossDomainMessenger internal constant WORLDCHAIN_L1_MESSENGER =
    IL1CrossDomainMessenger(0xf931a81D18B1766d15695ffc7c1920a62b7e710a);

  address internal constant WORLDCHAIN_CROSS_CHAIN_ACCOUNT =
    0xcb2436774C3e191c85056d248EF4260ce5f27A9D;

  address internal constant WORLDCHAIN_V3_FACTORY = 0x7a5028BDa40e7B173C278C5342087826455ea25a;

  address internal constant WORLDCHAIN_FEE_ADAPTER = 0x1CE9d4DfB474Ef9ea7dc0e804a333202e40d6201;

  address internal constant WORLDCHAIN_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

  address internal constant WORLDCHAIN_TOKEN_JAR = 0xbDb82c2dE7D8748A3e499e771604ef8ef8544918;

  // ─── Zora (owner = CrossChainAccount -> XDM) ───

  IL1CrossDomainMessenger internal constant ZORA_L1_MESSENGER =
    IL1CrossDomainMessenger(0xdC40a14d9abd6F410226f1E6de71aE03441ca506);

  address internal constant ZORA_CROSS_CHAIN_ACCOUNT = 0x36eEC182D0B24Df3DC23115D64DB521A93D5154f;

  address internal constant ZORA_V3_FACTORY = 0x7145F8aeef1f6510E92164038E1B6F8cB2c42Cbb;

  address internal constant ZORA_FEE_ADAPTER = 0xbfc49b47637a4DC9b7B8dE8E71BF41E519103B95;

  address internal constant ZORA_V2_FACTORY = 0x0F797dC7efaEA995bB916f268D919d0a1950eE3C;

  address internal constant ZORA_TOKEN_JAR = 0x4753C137002D802f45302b118E265c41140e73C2;

  // ─── Proposal ───

  string internal constant PROPOSAL_DESCRIPTION = "# Activate V3 and V2 Protocol Fees on Celo, Soneium, Worldchain, X Layer, and Zora\n\n"
    "This proposal activates Uniswap protocol fees on five L2 chains by transferring V3\n"
    "factory ownership to V3OpenFeeAdapter and setting V2 factory feeTo to TokenJar.\n\n"
    "## Phase 1: Activate via depositTransaction\n\n"
    "For **Soneium** and **X Layer**, the V3 factory and V2 feeToSetter are controlled by the\n"
    "aliased L1 Timelock. This proposal transfers V3 factory ownership to V3OpenFeeAdapter and\n"
    "sets V2 feeTo to TokenJar via OptimismPortal.depositTransaction().\n\n"
    "## Phase 2: Activate via XDM\n\n"
    "For **Celo**, **Worldchain**, and **Zora**, the V3 factory and V2 feeToSetter are controlled\n"
    "by CrossChainAccounts. This proposal transfers V3 factory ownership to V3OpenFeeAdapter and\n"
    "sets V2 feeTo to TokenJar via L1CrossDomainMessenger messages.\n\n"
    "- Celo: CrossChainAccount received V3/V2 control from the Wormhole Receiver in proposal 05\n"
    "- Worldchain: CrossChainAccount is the existing V2 feeToSetter\n"
    "- Zora: V2 feeToSetter transferred to CrossChainAccount by the Zora team pre-execution\n\n"
    "## Fee Configuration\n\n"
    "The V3OpenFeeAdapter on each chain is pre-configured with the same fee tier defaults as\n"
    "Ethereum mainnet:\n" "- 0.01% and 0.05% tiers: protocol fee = 1/4th of LP fees\n"
    "- 0.30% and 1.00% tiers: protocol fee = 1/6th of LP fees\n\n" "## Post-execution\n\n"
    "After this proposal, all chains will have a unified ownership model:\n"
    "- V3 factory -> owned by V3OpenFeeAdapter\n" "- V2 factory feeTo -> TokenJar\n"
    "- V3OpenFeeAdapter -> owned by CrossChainAccount\n"
    "- CrossChainAccount -> controlled by L1 Timelock via L2CrossDomainMessenger\n"
    "- Fee parameters adjustable by governance via CrossChainAccount\n";

  function setUp() public {}

  /// @notice Build the proposal actions
  function _buildActions() internal pure returns (ProposalAction[] memory actions) {
    require(SONEIUM_FEE_ADAPTER != address(0), "Soneium fee adapter address not set");
    require(SONEIUM_TOKEN_JAR != address(0), "Soneium TokenJar address not set");
    require(XLAYER_FEE_ADAPTER != address(0), "XLayer fee adapter address not set");
    require(XLAYER_TOKEN_JAR != address(0), "XLayer TokenJar address not set");
    require(CELO_CROSS_CHAIN_ACCOUNT != address(0), "Celo CrossChainAccount address not set");
    require(CELO_FEE_ADAPTER != address(0), "Celo fee adapter address not set");
    require(CELO_TOKEN_JAR != address(0), "Celo TokenJar address not set");
    require(WORLDCHAIN_FEE_ADAPTER != address(0), "Worldchain fee adapter address not set");
    require(WORLDCHAIN_TOKEN_JAR != address(0), "Worldchain TokenJar address not set");
    require(ZORA_FEE_ADAPTER != address(0), "Zora fee adapter address not set");
    require(ZORA_TOKEN_JAR != address(0), "Zora TokenJar address not set");

    actions = new ProposalAction[](10);

    // ═══ Phase 1: Activate via depositTransaction (Soneium & XLayer) ═══

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

    // Action 1: Soneium — depositTransaction to set V2 feeTo to TokenJar
    // L1 Timelock -> OptimismPortal(Soneium) -> V2Factory.setFeeTo(tokenJar)
    // msg.sender on L2 = aliased Timelock = current feeToSetter
    actions[1] = ProposalAction({
      target: address(SONEIUM_PORTAL),
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IOptimismPortal.depositTransaction,
        (
          SONEIUM_V2_FACTORY,
          0,
          DEPOSIT_GAS_LIMIT,
          false,
          abi.encodeCall(IUniswapV2Factory.setFeeTo, (SONEIUM_TOKEN_JAR))
        )
      )
    });

    // Action 2: XLayer — depositTransaction to transfer factory to fee adapter
    // L1 Timelock -> OptimismPortal(XLayer) -> factory.setOwner(feeAdapter)
    // msg.sender on L2 = aliased Timelock = current factory owner
    actions[2] = ProposalAction({
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

    // Action 3: XLayer — depositTransaction to set V2 feeTo to TokenJar
    // L1 Timelock -> OptimismPortal(XLayer) -> V2Factory.setFeeTo(tokenJar)
    // msg.sender on L2 = aliased Timelock = current feeToSetter
    actions[3] = ProposalAction({
      target: address(XLAYER_PORTAL),
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IOptimismPortal.depositTransaction,
        (
          XLAYER_V2_FACTORY,
          0,
          DEPOSIT_GAS_LIMIT,
          false,
          abi.encodeCall(IUniswapV2Factory.setFeeTo, (XLAYER_TOKEN_JAR))
        )
      )
    });

    // ═══ Phase 2: Activate via XDM (Celo) ═══

    // Action 4: Celo — XDM to transfer factory to fee adapter
    // L1 Timelock -> L1CrossDomainMessenger(Celo) -> CrossChainAccount.forward(factory, setOwner)
    // NOTE: CrossChainAccount received factory ownership from Wormhole Receiver in proposal 05
    actions[4] = ProposalAction({
      target: address(CELO_L1_MESSENGER),
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IL1CrossDomainMessenger.sendMessage,
        (
          CELO_CROSS_CHAIN_ACCOUNT,
          abi.encodeCall(
            ICrossChainAccount.forward,
            (CELO_V3_FACTORY, abi.encodeCall(IUniswapV3Factory.setOwner, (CELO_FEE_ADAPTER)))
          ),
          XDM_GAS_LIMIT
        )
      )
    });

    // Action 5: Celo — set V2 factory feeTo to TokenJar
    // L1 Timelock -> L1CrossDomainMessenger(Celo) -> CrossChainAccount.forward(V2Factory, setFeeTo)
    // NOTE: CrossChainAccount became feeToSetter via Wormhole handoff in proposal 05
    actions[5] = ProposalAction({
      target: address(CELO_L1_MESSENGER),
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IL1CrossDomainMessenger.sendMessage,
        (
          CELO_CROSS_CHAIN_ACCOUNT,
          abi.encodeCall(
            ICrossChainAccount.forward,
            (CELO_V2_FACTORY, abi.encodeCall(IUniswapV2Factory.setFeeTo, (CELO_TOKEN_JAR)))
          ),
          XDM_GAS_LIMIT
        )
      )
    });

    // ═══ Phase 2: Activate via XDM (Worldchain & Zora) ═══

    // Action 6: Worldchain — XDM to transfer factory to fee adapter
    // L1 Timelock -> L1CrossDomainMessenger -> CrossChainAccount.forward(factory, setOwner)
    actions[6] = ProposalAction({
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

    // Action 7: Worldchain — set V2 factory feeTo to TokenJar
    // L1 Timelock -> L1CrossDomainMessenger -> CrossChainAccount.forward(V2Factory, setFeeTo)
    actions[7] = ProposalAction({
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
              WORLDCHAIN_V2_FACTORY,
              abi.encodeCall(IUniswapV2Factory.setFeeTo, (WORLDCHAIN_TOKEN_JAR))
            )
          ),
          XDM_GAS_LIMIT
        )
      )
    });

    // Action 8: Zora — XDM to transfer factory to fee adapter
    // L1 Timelock -> L1CrossDomainMessenger -> CrossChainAccount.forward(factory, setOwner)
    actions[8] = ProposalAction({
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

    // Action 9: Zora — set V2 factory feeTo to TokenJar
    // L1 Timelock -> L1CrossDomainMessenger -> CrossChainAccount.forward(V2Factory, setFeeTo)
    // NOTE: Zora team transferred feeToSetter to CrossChainAccount pre-execution
    actions[9] = ProposalAction({
      target: address(ZORA_L1_MESSENGER),
      value: 0,
      signature: "",
      data: abi.encodeCall(
        IL1CrossDomainMessenger.sendMessage,
        (
          ZORA_CROSS_CHAIN_ACCOUNT,
          abi.encodeCall(
            ICrossChainAccount.forward,
            (ZORA_V2_FACTORY, abi.encodeCall(IUniswapV2Factory.setFeeTo, (ZORA_TOKEN_JAR)))
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

    console2.log("=== Proposal: Activate V3 and V2 Fees on L2s ===");
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
