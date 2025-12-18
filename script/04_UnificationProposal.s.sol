// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {AttestationRequestData, AttestationRequest, IEAS} from "eas-contracts/IEAS.sol";
import {Script} from "forge-std/Script.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {MainnetDeployer} from "./deployers/MainnetDeployer.sol";
import {IUniswapV2Factory} from "briefcase/protocols/v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV3Factory} from "briefcase/protocols/v3-core/interfaces/IUniswapV3Factory.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {AgreementAnchor} from "dao-signer/src/AgreementAnchor.sol";
import {AgreementResolver} from "dao-signer/src/AgreementResolver.sol";

struct ProposalAction {
  address target;
  uint256 value;
  string signature;
  bytes data;
}

contract UnificationProposal is Script, StdAssertions {
  AgreementAnchor public constant AGREEMENT_ANCHOR_1 =
    AgreementAnchor(0xC707467e7fb43Fe7Cc55264F892Dd2D7f8Fc27C8);
  AgreementAnchor public constant AGREEMENT_ANCHOR_2 =
    AgreementAnchor(0x33A56942Fe57f3697FE0fF52aB16cb0ba9b8eadd);
  AgreementAnchor public constant AGREEMENT_ANCHOR_3 =
    AgreementAnchor(0xF9F85a17cC6De9150Cd139f64b127976a1dE91D1);
  string internal constant PROPOSAL_DESCRIPTION = "# UNIfication\n\n"
    "*This vote covers the [UNIfication proposal](https://gov.uniswap.org/t/unification-proposal/25881) "
    "and includes the final copy of the services agreement, indemnification agreements for the independent "
    "negotiation committee, final spec, and an updated list of v3 pools that has been refreshed to reflect "
    "the latest available data. We recommend reading the full details before voting.*\n\n"
    "## Proposal Spec\n\n" "If this proposal passes, it will execute eight function calls:\n\n"
    "```\n" "/// Burn 100m UNI\n" "UNI.transfer(0xdead, 100_000_000 ether);\n\n"
    "/// Set the owner of the v3 factory on mainnet to the configured fee controller to enable v3 protocol fees\n"
    "V3_FACTORY.setOwner(address(v3FeeController));\n\n"
    "/// Change the FeeToSetter parameter on the v2 factory on mainnet to the Governance Timelock\n"
    "IOldV2FeeToSetter(V2_FACTORY.feeToSetter()).setFeeToSetter(TIMELOCK);\n\n"
    "/// Change the FeeTo parameter on the v2 factory on mainnet to enable v2 protocol fees\n"
    "V2_FACTORY.setFeeTo(address(tokenJar));\n\n"
    "/// Approve two years of vesting into the UNIVester smart contract\n"
    "/// UNI stays in treasury until vested and unvested UNI can be cancelled by setting approve back to 0\n"
    "UNI.approve(address(uniVesting), 40_000_000 ether);\n\n"
    "/// Execute the services agreement with Uniswap Labs on behalf of DUNI\n"
    "AgreementAnchor.attest(address(0xC707467e7fb43Fe7Cc55264F892Dd2D7f8Fc27C8));\n\n"
    "/// Execute the indemnification agreement with Hart Lambur on behalf of DUNI\n"
    "AgreementAnchor.attest(address(0x33A56942Fe57f3697FE0fF52aB16cb0ba9b8eadd));\n\n"
    "/// Execute the indemnification agreement with DAO Jones LLC on behalf of DUNI\n"
    "AgreementAnchor.attest(address(0xF9F85a17cC6De9150Cd139f64b127976a1dE91D1));\n" "```\n\n"
    "## Proposal\n\n" "*Hayden Adams, Ken Ng, Devin Walsh*\n\n"
    "Today, Uniswap Labs and the Uniswap Foundation are excited to make a joint governance proposal that "
    "turns on protocol fees and aligns incentives across the Uniswap ecosystem, positioning the Uniswap "
    "protocol to win as the default decentralized exchange for tokenized value.\n\n"
    "The protocol has processed ~$4 trillion in volume, made possible by thousands of developers, millions "
    "of liquidity providers, and hundreds of millions of swapping wallets.\n\n"
    "But the last several years have also come with obstacles: we've fought legal battles and navigated a "
    "hostile regulatory environment under Gensler's SEC. This climate has changed in the US, and milestones "
    "like Uniswap governance adopting [DUNI](https://gov.uniswap.org/t/governance-proposal-establish-uniswap-governance-as-duni-a-wyoming-duna/25770), "
    "the [DUNA](https://a16zcrypto.com/posts/article/duna-for-daos/), have prepared the Uniswap community for its next steps.\n\n"
    "This proposal comes as DeFi reaches an inflection point. Decentralized trading protocols are "
    "[rivaling](https://www.theblock.co/data/decentralized-finance/dex-non-custodial/dex-to-cex-spot-trade-volume) "
    "centralized platforms in performance and scale, tokens are going mainstream, and institutions are building "
    "on Uniswap and other DeFi protocols.\n\n"
    "This proposal establishes a long-term model for how the Uniswap ecosystem would operate, where protocol "
    "usage drives UNI burn and Uniswap Labs focuses on protocol development and growth. We propose to:\n\n"
    "1. Turn on Uniswap protocol fees and use these fees to burn UNI\n"
    "2. Send Unichain sequencer fees to this same UNI burn mechanism\n"
    "3. Build Protocol Fee Discount Auctions (PFDA) to increase LP returns and allow the protocol to internalize MEV\n"
    "4. Launch aggregator hooks, turning Uniswap v4 into an onchain aggregator that collects fees on external liquidity\n"
    "5. Burn 100 million UNI from the treasury representing the approximate amount of UNI that would have been burned if fees were on from the beginning\n"
    "6. Focus Labs on driving protocol development and growth, including turning off our interface, wallet, and API fees and contractually committing to only pursue initiatives that align with DUNI interests\n"
    "7. Move ecosystem teams from the Foundation to Labs, with a shared goal of protocol success, with growth and development funded from the treasury\n"
    "8. Migrate governance-owned Unisocks liquidity from Uniswap v1 on mainnet to v4 on Unichain and burn the LP position, locking in the supply curve forever\n\n"
    "### Protocol Fees\n\n"
    "The Uniswap protocol includes a fee switch that can only be turned on by a UNI governance vote. We propose "
    "that governance flip the fee switch and introduce a programmatic mechanism that burns UNI.\n\n"
    "#### Protocol Fee Rollout\n\n"
    "To minimize impact, we propose fees roll out over time, starting with v2 pools and a set of v3 pools that "
    "make up 80-95% of LP fees on Ethereum mainnet. From there, fees can be turned on for L2s, other L1s, v4, "
    "UniswapX, PFDA, and aggregator hooks.\n\n"
    "Uniswap v2 fee levels are hardcoded and governance must enable or disable fees across all v2 pools at once. "
    "With fees off, LP fees are 0.3%. Once activated, LP fees are 0.25% and protocol fees are 0.05%.\n\n"
    "Uniswap v3 has fixed swap fee tiers on mainnet, with protocol fees that are adjustable by governance and "
    "set at the individual pool level. Protocol fees for 0.01% and 0.05% pools would initially be set to 1/4th "
    "of LP fees. For 0.30% and 1% pools, protocol fees would be set to 1/6th of LP fees.\n\n"
    "Labs will assist the community in monitoring the impact of fees and may make recommendations to adjust. "
    "To improve efficiency, we propose governance votes on fee parameters skip the RFC process and move straight "
    "to Snapshot followed by an onchain vote.\n\n" "***Update 12/18:***\n\n"
    "The list of Uniswap v3 pools included in the proposal has been refreshed to reflect the latest available data. "
    "The full updated list can be found [here](https://github.com/Uniswap/protocol-fees/blob/main/merkle-generator/data/merkle-tree.json).\n\n"
    "#### Unichain Sequencer Fees\n\n"
    "Unichain launched just 9 months ago, and is already processing ~$100 billion in annualized DEX volume and "
    "~$7.5 million annualized sequencer fees.\n\n"
    "This proposal directs all Unichain sequencer fees, after L1 data costs and the 15% to Optimism, into the burn mechanism.\n\n"
    "#### Fee Mechanism for MEV Internalization\n\n"
    "The Protocol Fee Discount Auction (PFDA) is designed to improve LP performance and add a new source of "
    "protocol fees by internalizing MEV that would otherwise go to searchers or validators.\n\n"
    "This mechanism auctions off the right to swap without paying the protocol fee for a single address for a "
    "short window of time, with the winning bid going to the UNI burn. Through this process, MEV that would "
    "typically go to validators instead burns UNI. For a detailed breakdown of this mechanism, read the "
    "[whitepaper](https://drive.google.com/file/d/1qhZFLTGOOHBx9OZW00dt5DzqEY0C3lhr/view?usp=sharing).\n\n"
    "Early analysis shows these discount auctions could increase LP returns by about $0.06-$0.26 for every $10k "
    "traded, a significant improvement given that LP returns typically range between -$1.00 and $1.00 for this "
    "amount of volume.\n\n" "#### Aggregator Hooks\n\n"
    "Uniswap v4 introduced hooks, turning the protocol into a developer platform with infinite possibilities for "
    "innovation. Labs is excited to be one of the many teams unlocking new functionality using hooks, starting "
    "with aggregation.\n\n"
    "These hooks source liquidity from other onchain protocols and add a programmatic UNI burn on top, turning "
    "Uniswap v4 itself into an aggregator that anyone can integrate.\n\n"
    "Labs will integrate aggregator hooks into its frontend and API, providing users access to more sources of "
    "onchain liquidity in a way that benefits the Uniswap ecosystem.\n\n"
    "#### Retroactive Burn\n\n"
    "Many community members wish the fee switch had been turned on earlier as UNI holders have missed out on years "
    "of fees on ~$4 trillion in Uniswap protocol volume. Alas, we cannot turn back the clock...  ***or can we***?\n\n"
    "We propose a retroactive burn of 100 million UNI from the treasury. This is an estimate of what might have "
    "been burned if the protocol fee switch had been active at token launch.\n\n"
    "#### Technical Implementation\n\n"
    "Each fee source requires an adapter contract, that sends fees into an immutable onchain contract called "
    "[TokenJar](http://docs.uniswap.org/contracts/protocol-fee/technical-reference/TokenJar) where they accumulate. "
    "Fees can only be withdrawn from TokenJar if UNI is burned in another smart contract called "
    "[Firepit](http://docs.uniswap.org/contracts/protocol-fee/technical-reference/FirePit).\n\n"
    "TokenJar and Firepit are already implemented, along with adapters for v2, v3, and Unichain. PFDA, v4, "
    "aggregator hooks, and bridge adapters for fees on L2s and other L1s are in progress and will be introduced "
    "through future governance proposals.\n\n"
    "Detailed documentation on protocol fees and UNI burn can be found "
    "[here](https://docs.uniswap.org/contracts/protocol-fee/overview).\n\n"
    "### UNIfication and Growth Budget\n\n"
    "Labs led development of every version of the Uniswap protocol, grew the initial community, popularized AMMs "
    "and DeFi, and launched products used by tens of millions. Foundation expanded this ecosystem through grants, "
    "governance support, and community growth.\n\n"
    "We propose unifying these efforts by transitioning Foundation teams to Labs, as Labs shifts its focus to "
    "helping make Uniswap protocol the default exchange for all tokenized value, funded through a growth budget "
    "from the treasury.\n\n" "#### Uniswap Foundation Activities Move to Uniswap Labs\n\n"
    "With the approval of this proposal, Labs will take on operational functions historically managed by the "
    "Foundation, including ecosystem support and funding, governance support, and developer relations.\n\n"
    "Hayden Adams and Callil Capuozzo will join the existing Foundation board of Devin Walsh, Hart Lambur, and "
    "Ken Ng, bringing the board to five members. Most Foundation employees will move to Labs, except for a small "
    "team focused on grants and incentives. This team will deploy the Foundation's remaining budget "
    "[consistent with its mission](https://www.uniswapfoundation.org/blog/unification), after which future grants "
    "will come from the growth budget under Labs.\n\n"
    "#### Labs Focuses on Uniswap Protocol Growth and Development\n\n"
    "This proposal aligns Labs' incentives with the Uniswap ecosystem. If approved, Labs will shift its focus from "
    "monetizing its interfaces to protocol growth and development. Labs' fees on the interface, wallet, and API "
    "will be set to zero.\n\n"
    "These products already drive significant organic volume for the protocol. Removing fees makes them even more "
    "competitive and brings in more high quality volume and integrations, leading to better outcomes for LPs and "
    "the entire Uniswap ecosystem.\n\n"
    "Monetization of Labs interfaces will continue to evolve over time and any fees on volume originating from "
    "these products will benefit the Uniswap ecosystem.\n\n"
    "Labs will focus on both sides of the protocol's flywheel - supply of liquidity and demand for volume. Below "
    "are just a few of the roadmap items ahead:\n\n"
    "* **Improve LP outcomes and protocol liquidity.** Deploy the Protocol Fee Discount Auction and LVR-reducing "
    "hooks to capture more value for LPs and the protocol. Strengthen protocol leadership on strategic pairs, "
    "including dynamic fee hooks and stable-stable hooks. Add more sources of liquidity to the Uniswap protocol "
    "through aggregator hooks.\n"
    "* **Drive Uniswap protocol integrations and onboard new ecosystem players.** Accelerate adoption through "
    "strategic partnerships, grants, and incentives that bring new participants onchain. Provide SDKs, documentation, "
    "and even a dedicated engineering team to help partners build on the protocol.\n"
    "* **Accelerate developer adoption of the protocol with Uniswap API.** Pivot the API from a profit-generating "
    "product to a zero margin distribution method, expanding the protocol to more platforms and products, including "
    "those that previously competed with Labs products. Launch self-serve developer portal for key provisioning and "
    "allow integrators to add and rebalance liquidity directly through the API.\n"
    "* **Drive protocol usage with Labs' interfaces.** Use the interface and wallet to drive more volume to the "
    "protocol by making it free, investing heavily in LP UX, and adding new features like dollar-cost-averaging, "
    "improved crosschain swaps, gas abstraction, and more.\n"
    "* **Empower hook builders.** Provide engineering support, routing, support in Labs' interfaces, grants and more.\n"
    "* **Establish Unichain as a leading liquidity hub.** Optimize Unichain for low-cost, high-performance AMM "
    "trading which attracts LPs, asset issuers, and other protocols. Make Uniswap protocol on Unichain the lowest "
    "cost place to trade in Labs' interface and API by sponsoring gas.\n"
    "* **Bring more assets to Uniswap.** Deploy Uniswap protocol wherever new assets live. Build and invest in "
    "liquidity bootstrapping tools and token launchers, RWA partnerships and bridging of non-EVM assets to Unichain.\n\n"
    "Labs will also accelerate growth through builder programs, grants, incentives, partnerships, M&A, venture, "
    "onboarding institutions, and exploring moonshot efforts to unlock new value for the Uniswap ecosystem. We will "
    "provide regular updates to the community, including budget reports, frequent product and growth updates, and "
    "real-time dashboards giving visibility into our impact.\n\n" "#### The Growth Budget\n\n"
    "We propose governance create an annual growth budget of 20M UNI, distributed quarterly using a "
    "[vesting contract](https://github.com/Uniswap/protocol-fees/blob/main/src/UNIVesting.sol) starting January 1, "
    "2026, to fund protocol growth and development.\n\n"
    "The growth budget would be governed by a services agreement between Labs and "
    "[DUNI](https://gov.uniswap.org/t/governance-proposal-establish-uniswap-governance-as-duni-a-wyoming-duna/25770). "
    "This would include an explicit commitment from Labs to maintain alignment between its activities and DUNI, "
    "ensuring Labs does not pursue strategies that conflict with token holder interests.\n\n"
    "The Foundation will coordinate this process in its role as "
    "[Ministerial Agent](https://gov.uniswap.org/t/governance-proposal-establish-uniswap-governance-as-duni-a-wyoming-duna/25770#p-57430-ministerial-agent-agreement-overview-9) "
    "to DUNI. If the Snapshot vote passes, an independent committee composed of "
    "[Ben Jones](https://x.com/ben_chain?lang=en) and [Hart Lambur](https://x.com/hal2001?lang=en) will be appointed "
    "by the Foundation to lead negotiations based on this "
    "[draft](https://drive.google.com/file/d/1yXv2fm1XMr1eOsSMzG4DloGzvkFEYc1-/view?usp=sharing) letter of intent, "
    "with [Cooley LLP](https://www.cooley.com/) serving as the committee's external counsel. The final negotiated "
    "agreement will be included in this governance proposal as part of the full onchain vote, and executed on its passing.\n\n"
    "***Update 12/18:***\n\n" "***Final services agreement between DUNI and Uniswap Labs***\n\n"
    "The [final services agreement](https://drive.google.com/file/d/1FxtK846m9CKQ9UqEnBt7uHRRMu9eTifs/view?usp=drive_link) "
    "reflects negotiations between the Uniswap Foundation's "
    "[independent committee](https://gov.uniswap.org/t/unification-proposal/25881#p-57882-the-growth-budget-13), "
    "acting as Ministerial Agent to DUNI, and Uniswap Labs following the temperature check, and does include "
    "deviations from the previously posted Letter of Intent.\n\n"
    "Hash: 0xb7a5a04f613e49ce4a8c2fb142a37c6781bda05c62d46a782f36bb6e97068d3b\n\n"
    "***Indemnification agreements for the independent negotiation committee***\n\n"
    "These agreements indemnify the members of the independent negotiation committee "
    "([Hart Lambur](https://drive.google.com/file/d/1kgq66KcAGD5mZzZrW28S8n-XuQS0PH8f/view?usp=drive_link) and "
    "[Ben Jones](https://drive.google.com/file/d/18Mp0Honnb3nxGCx0k_aU4wBVncAwDA4F/view?usp=drive_link)), or their "
    "respective service providers, as applicable, for the services they provided in negotiating the SPA.\n\n"
    "Hashes:\n" "0x96861f436ef11b12dc8df810ab733ea8c7ea16cad6fd476942075ec28d5cf18a (Hart Lambur), "
    "0x576613b871f61f21e14a7caf5970cb9e472e82f993e10e13e2d995703471f011 (Ben Jones)\n\n"
    "### Lock the Socks\n\n" "Unisocks have a long history, ranging between "
    "[fun](https://x.com/EthereumFilm/status/1824171012696707244), "
    "[fashion](https://x.com/CL207/status/1550155749736689664), "
    "[flex](https://x.com/jaysonhobby/status/1382389435329744896), "
    "[weird](https://x.com/PleasrDAO/status/1636758148378918917), "
    "[weirder](https://x.com/cherdougie/status/1638703664016572419), "
    "[even weirder](https://x.com/Snowden/status/1592203313323593731), and gross (we're not linking this one). "
    "They were [launched](https://x.com/Uniswap/status/1126506339075641344) by Labs in May 2019 as the first "
    "tokenized socks to trade on Uniswap protocol, or anywhere probably.\n\n"
    "When Labs launched UNI in September 2020, it "
    "[transferred](https://etherscan.io/tx/0xa1c6a16481fe12f2003faa6f5797af8d6ab06512d10bd5010edf63d385c7e449) "
    "ownership of the original Uniswap v1 SOCKS/ETH liquidity position to Uniswap governance, where it has sat "
    "dormant ever since. We propose that governance move this position from Uniswap v1 on mainnet to Uniswap v4 "
    "on Unichain and transfer the LP position to a burn address, locking it forever.\n\n"
    "This would ensure that this liquidity can never be withdrawn in the future, permanently locking in the "
    "original price curve and realizing the Unisocks vision. Also, the pink socks belong on the pink chain and "
    "\"Uniswap v4\" rhymes with \"wore\" - which is what you do with socks.\n\n"
    "Due to technical complexity, this migration would be executed through a separate onchain vote.\n\n"
    "### Thank you\n\n"
    "Uniswap protocol wouldn't be here without the LPs, swappers, builders, and community members who've helped "
    "the protocol become the largest decentralized exchange in the world. This proposal builds on that foundation, "
    "and sets the ecosystem up for the next phase of growth.\n\n"
    "Thank you to everyone who has been part of the journey so far. We're just getting started!\n\n"
    "**Resources:**\n\n" "* [Fee documentation](https://github.com/uniswap/protocol-fees)\n"
    "* [Fee contracts](https://github.com/Uniswap/protocol-fees/tree/main/src)\n"
    "* [Protocol Fee Discount Auction whitepaper](https://drive.google.com/file/d/1qhZFLTGOOHBx9OZW00dt5DzqEY0C3lhr/view?usp=sharing)\n"
    "* [Draft letter of intent](https://drive.google.com/file/d/1yXv2fm1XMr1eOsSMzG4DloGzvkFEYc1-/view?usp=sharing)\n"
    "* [Final services agreement](https://drive.google.com/file/d/1yXv2fm1XMr1eOsSMzG4DloGzvkFEYc1-/view?usp=sharing)\n"
    "* [Indemnification agreement for Hart Lambur](https://drive.google.com/file/d/1yXv2fm1XMr1eOsSMzG4DloGzvkFEYc1-/view?usp=sharing)\n"
    "* [Indemnification agreement for Ben Jones](https://drive.google.com/file/d/18Mp0Honnb3nxGCx0k_aU4wBVncAwDA4F/view?usp=drive_link)\n";

  IGovernorBravo internal constant GOVERNOR_BRAVO =
    IGovernorBravo(0x408ED6354d4973f66138C91495F2f2FCbd8724C3);
  IERC20 UNI = IERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
  IUniswapV2Factory public V2_FACTORY =
    IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
  IUniswapV3Factory public constant V3_FACTORY =
    IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
  address public constant OLD_FEE_TO_SETTER = 0x18e433c7Bf8A2E1d0197CE5d8f9AFAda1A771360;

  // EAS Constants
  IEAS internal constant EAS = IEAS(0xA1207F3BBa224E2c9c3c6D5aF63D0eb1582Ce587);
  bytes32 public constant AGREEMENT_SCHEMA_UID =
    0x504f10498bcdb19d4960412dbade6fa1530b8eed65c319f15cbe20fadafe56bd;

  function setUp() public {}

  function run(MainnetDeployer deployer) public {
    vm.startBroadcast();
    ProposalAction[] memory actions = _run(deployer);
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

  function runAnvil(MainnetDeployer deployer) public {
    vm.startBroadcast(V3_FACTORY.owner());
    ProposalAction[] memory actions = _run(deployer);
    for (uint256 i = 0; i < actions.length; i++) {
      ProposalAction memory action = actions[i];
      (bool success,) = action.target.call{value: action.value}(action.data);
      require(success, "Call failed");
    }
    vm.stopBroadcast();
  }

  function runPranked(MainnetDeployer deployer) public {
    vm.startPrank(V3_FACTORY.owner());
    ProposalAction[] memory actions = _run(deployer);
    for (uint256 i = 0; i < actions.length; i++) {
      ProposalAction memory action = actions[i];
      (bool success,) = action.target.call{value: action.value}(action.data);
      require(success, "Call failed");
    }
    vm.stopPrank();
  }

  function _run(MainnetDeployer deployer) public returns (ProposalAction[] memory actions) {
    address timelock = deployer.V3_FACTORY().owner();

    // --- Proposal Actions Setup ---
    actions = new ProposalAction[](8);

    // Burn 100M UNI
    actions[0] = ProposalAction({
      target: address(UNI),
      value: 0,
      signature: "",
      data: abi.encodeCall(UNI.transfer, (address(0xdead), 100_000_000 ether))
    });

    // Set the owner of the v3 factory to the configured fee controller
    actions[1] = ProposalAction({
      target: address(V3_FACTORY),
      value: 0,
      signature: "",
      data: abi.encodeCall(V3_FACTORY.setOwner, (address(deployer.V3_FEE_ADAPTER())))
    });

    // Update the v2 fee to setter to the timelock
    actions[2] = ProposalAction({
      target: address(OLD_FEE_TO_SETTER),
      value: 0,
      signature: "",
      data: abi.encodeCall(IFeeToSetter.setFeeToSetter, (timelock))
    });

    // Set the recipient of v2 protocol fees to the token jar
    actions[3] = ProposalAction({
      target: address(V2_FACTORY),
      value: 0,
      signature: "",
      data: abi.encodeCall(V2_FACTORY.setFeeTo, (address(deployer.TOKEN_JAR())))
    });

    // Approve two years of vesting to the UNIvester smart contract
    // UNI stays in treasury until vested and unvested UNI can be cancelled by setting approve back
    // to 0
    actions[4] = ProposalAction({
      target: address(UNI),
      value: 0,
      signature: "",
      data: abi.encodeCall(UNI.approve, (address(deployer.UNI_VESTING()), 40_000_000 ether))
    });

    // DAO attests to Agreement 1
    if (address(AGREEMENT_ANCHOR_1) != address(0)) {
      actions[5] = ProposalAction({
        target: address(EAS),
        value: 0,
        signature: "",
        data: abi.encodeCall(
          EAS.attest,
          (AttestationRequest({
              schema: AGREEMENT_SCHEMA_UID,
              data: AttestationRequestData({
                recipient: address(AGREEMENT_ANCHOR_1),
                expirationTime: 0,
                revocable: false,
                refUID: bytes32(0),
                data: abi.encode(AGREEMENT_ANCHOR_1.CONTENT_HASH()),
                value: 0
              })
            }))
        )
      });
    }

    // DAO attests to Agreement 2
    if (address(AGREEMENT_ANCHOR_2) != address(0)) {
      actions[6] = ProposalAction({
        target: address(EAS),
        value: 0,
        signature: "",
        data: abi.encodeCall(
          EAS.attest,
          (AttestationRequest({
              schema: AGREEMENT_SCHEMA_UID,
              data: AttestationRequestData({
                recipient: address(AGREEMENT_ANCHOR_2),
                expirationTime: 0,
                revocable: false,
                refUID: bytes32(0),
                data: abi.encode(AGREEMENT_ANCHOR_2.CONTENT_HASH()),
                value: 0
              })
            }))
        )
      });
    }

    // DAO attests to Agreement 3
    if (address(AGREEMENT_ANCHOR_3) != address(0)) {
      actions[7] = ProposalAction({
        target: address(EAS),
        value: 0,
        signature: "",
        data: abi.encodeCall(
          EAS.attest,
          (AttestationRequest({
              schema: AGREEMENT_SCHEMA_UID,
              data: AttestationRequestData({
                recipient: address(AGREEMENT_ANCHOR_3),
                expirationTime: 0,
                revocable: false,
                refUID: bytes32(0),
                data: abi.encode(AGREEMENT_ANCHOR_3.CONTENT_HASH()),
                value: 0
              })
            }))
        )
      });
    }
  }
}

// interface for:
// https://etherscan.io/address/0x18e433c7Bf8A2E1d0197CE5d8f9AFAda1A771360#code
// the current V2_FACTORY.feeToSetter()
interface IFeeToSetter {
  function setFeeToSetter(address) external;
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
