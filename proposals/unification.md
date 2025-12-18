## Proposal Spec

If this proposal passes, it will execute eight function calls:

```
/// Burn 100m UNI
UNI.transfer(0xdead, 100_000_000 ether);

/// Set the owner of the v3 factory on mainnet to the configured fee controller to enable v3 protocol fees
V3_FACTORY.setOwner(address(v3FeeController));

/// Change the FeeToSetter parameter on the v2 factory on mainnet to the Governance Timelock
IOldV2FeeToSetter(V2_FACTORY.feeToSetter()).setFeeToSetter(TIMELOCK);

/// Change the FeeTo parameter on the v2 factory on mainnet to enable v2 protocol fees
V2_FACTORY.setFeeTo(address(tokenJar));

/// Approve two years of vesting into the UNIVester smart contract
/// UNI stays in treasury until vested and unvested UNI can be cancelled by setting approve back to 0
UNI.approve(address(uniVesting), 40_000_000 ether);

/// Execute the services agreement with Uniswap Labs on behalf of DUNI
AgreementAnchor.attest(address(0xC707467e7fb43Fe7Cc55264F892Dd2D7f8Fc27C8));

/// Execute the indemnification agreement with Hart Lambur on behalf of DUNI
AgreementAnchor.attest(address(0x33A56942Fe57f3697FE0fF52aB16cb0ba9b8eadd));

/// Execute the indemnification agreement with DAO Jones LLC on behalf of DUNI
AgreementAnchor.attest(address(0xF9F85a17cC6De9150Cd139f64b127976a1dE91D1));
```

## Proposal

*Hayden Adams, Ken Ng, Devin Walsh*

Today, Uniswap Labs and the Uniswap Foundation are excited to make a joint governance proposal that turns on protocol fees and aligns incentives across the Uniswap ecosystem, positioning the Uniswap protocol to win as the default decentralized exchange for tokenized value.

The protocol has processed ~$4 trillion in volume, made possible by thousands of developers, millions of liquidity providers, and hundreds of millions of swapping wallets.

But the last several years have also come with obstacles: we've fought legal battles and navigated a hostile regulatory environment under Gensler's SEC. This climate has changed in the US, and milestones like Uniswap governance adopting [DUNI](https://gov.uniswap.org/t/governance-proposal-establish-uniswap-governance-as-duni-a-wyoming-duna/25770), the [DUNA](https://a16zcrypto.com/posts/article/duna-for-daos/), have prepared the Uniswap community for its next steps.

This proposal comes as DeFi reaches an inflection point. Decentralized trading protocols are [rivaling](https://www.theblock.co/data/decentralized-finance/dex-non-custodial/dex-to-cex-spot-trade-volume) centralized platforms in performance and scale, tokens are going mainstream, and institutions are building on Uniswap and other DeFi protocols.

This proposal establishes a long-term model for how the Uniswap ecosystem would operate, where protocol usage drives UNI burn and Uniswap Labs focuses on protocol development and growth. We propose to:

1. Turn on Uniswap protocol fees and use these fees to burn UNI
2. Send Unichain sequencer fees to this same UNI burn mechanism
3. Build Protocol Fee Discount Auctions (PFDA) to increase LP returns and allow the protocol to internalize MEV
4. Launch aggregator hooks, turning Uniswap v4 into an onchain aggregator that collects fees on external liquidity
5. Burn 100 million UNI from the treasury representing the approximate amount of UNI that would have been burned if fees were on from the beginning
6. Focus Labs on driving protocol development and growth, including turning off our interface, wallet, and API fees and contractually committing to only pursue initiatives that align with DUNI interests
7. Move ecosystem teams from the Foundation to Labs, with a shared goal of protocol success, with growth and development funded from the treasury
8. Migrate governance-owned Unisocks liquidity from Uniswap v1 on mainnet to v4 on Unichain and burn the LP position, locking in the supply curve forever

### Protocol Fees

The Uniswap protocol includes a fee switch that can only be turned on by a UNI governance vote. We propose that governance flip the fee switch and introduce a programmatic mechanism that burns UNI.

#### Protocol Fee Rollout

To minimize impact, we propose fees roll out over time, starting with v2 pools and a set of v3 pools that make up 80-95% of LP fees on Ethereum mainnet. From there, fees can be turned on for L2s, other L1s, v4, UniswapX, PFDA, and aggregator hooks.

Uniswap v2 fee levels are hardcoded and governance must enable or disable fees across all v2 pools at once. With fees off, LP fees are 0.3%. Once activated, LP fees are 0.25% and protocol fees are 0.05%.

Uniswap v3 has fixed swap fee tiers on mainnet, with protocol fees that are adjustable by governance and set at the individual pool level. Protocol fees for 0.01% and 0.05% pools would initially be set to 1/4th of LP fees. For 0.30% and 1% pools, protocol fees would be set to 1/6th of LP fees.

Labs will assist the community in monitoring the impact of fees and may make recommendations to adjust. To improve efficiency, we propose governance votes on fee parameters skip the RFC process and move straight to Snapshot followed by an onchain vote.

***Update 12/18:***

The list of Uniswap v3 pools included in the proposal has been refreshed to reflect the latest available data. The full updated list can be found [here](https://github.com/Uniswap/protocol-fees/blob/main/merkle-generator/data/merkle-tree.json).

#### Unichain Sequencer Fees

Unichain launched just 9 months ago, and is already processing ~$100 billion in annualized DEX volume and ~$7.5 million annualized sequencer fees.

This proposal directs all Unichain sequencer fees, after L1 data costs and the 15% to Optimism, into the burn mechanism.

#### Fee Mechanism for MEV Internalization

The Protocol Fee Discount Auction (PFDA) is designed to improve LP performance and add a new source of protocol fees by internalizing MEV that would otherwise go to searchers or validators.

This mechanism auctions off the right to swap without paying the protocol fee for a single address for a short window of time, with the winning bid going to the UNI burn. Through this process, MEV that would typically go to validators instead burns UNI. For a detailed breakdown of this mechanism, read the [whitepaper](https://drive.google.com/file/d/1qhZFLTGOOHBx9OZW00dt5DzqEY0C3lhr/view?usp=sharing).

Early analysis shows these discount auctions could increase LP returns by about $0.06-$0.26 for every $10k traded, a significant improvement given that LP returns typically range between -$1.00 and $1.00 for this amount of volume.

#### Aggregator Hooks

Uniswap v4 introduced hooks, turning the protocol into a developer platform with infinite possibilities for innovation. Labs is excited to be one of the many teams unlocking new functionality using hooks, starting with aggregation.

These hooks source liquidity from other onchain protocols and add a programmatic UNI burn on top, turning Uniswap v4 itself into an aggregator that anyone can integrate.

Labs will integrate aggregator hooks into its frontend and API, providing users access to more sources of onchain liquidity in a way that benefits the Uniswap ecosystem.

#### Retroactive Burn

Many community members wish the fee switch had been turned on earlier as UNI holders have missed out on years of fees on ~$4 trillion in Uniswap protocol volume. Alas, we cannot turn back the clock...  ***or can we***?

We propose a retroactive burn of 100 million UNI from the treasury. This is an estimate of what might have been burned if the protocol fee switch had been active at token launch.

#### Technical Implementation

Each fee source requires an adapter contract, that sends fees into an immutable onchain contract called [TokenJar](http://docs.uniswap.org/contracts/protocol-fee/technical-reference/TokenJar) where they accumulate. Fees can only be withdrawn from TokenJar if UNI is burned in another smart contract called [Firepit](http://docs.uniswap.org/contracts/protocol-fee/technical-reference/FirePit).

TokenJar and Firepit are already implemented, along with adapters for v2, v3, and Unichain. PFDA, v4, aggregator hooks, and bridge adapters for fees on L2s and other L1s are in progress and will be introduced through future governance proposals.

Detailed documentation on protocol fees and UNI burn can be found [here](https://docs.uniswap.org/contracts/protocol-fee/overview).

### UNIfication and Growth Budget

Labs led development of every version of the Uniswap protocol, grew the initial community, popularized AMMs and DeFi, and launched products used by tens of millions. Foundation expanded this ecosystem through grants, governance support, and community growth.

We propose unifying these efforts by transitioning Foundation teams to Labs, as Labs shifts its focus to helping make Uniswap protocol the default exchange for all tokenized value, funded through a growth budget from the treasury.

#### Uniswap Foundation Activities Move to Uniswap Labs

With the approval of this proposal, Labs will take on operational functions historically managed by the Foundation, including ecosystem support and funding, governance support, and developer relations.

Hayden Adams and Callil Capuozzo will join the existing Foundation board of Devin Walsh, Hart Lambur, and Ken Ng, bringing the board to five members. Most Foundation employees will move to Labs, except for a small team focused on grants and incentives. This team will deploy the Foundation's remaining budget [consistent with its mission](https://www.uniswapfoundation.org/blog/unification), after which future grants will come from the growth budget under Labs.

#### Labs Focuses on Uniswap Protocol Growth and Development

This proposal aligns Labs' incentives with the Uniswap ecosystem. If approved, Labs will shift its focus from monetizing its interfaces to protocol growth and development. Labs' fees on the interface, wallet, and API will be set to zero.

These products already drive significant organic volume for the protocol. Removing fees makes them even more competitive and brings in more high quality volume and integrations, leading to better outcomes for LPs and the entire Uniswap ecosystem.

Monetization of Labs interfaces will continue to evolve over time and any fees on volume originating from these products will benefit the Uniswap ecosystem.

Labs will focus on both sides of the protocol's flywheel - supply of liquidity and demand for volume. Below are just a few of the roadmap items ahead:

* **Improve LP outcomes and protocol liquidity.** Deploy the Protocol Fee Discount Auction and LVR-reducing hooks to capture more value for LPs and the protocol. Strengthen protocol leadership on strategic pairs, including dynamic fee hooks and stable-stable hooks. Add more sources of liquidity to the Uniswap protocol through aggregator hooks.
* **Drive Uniswap protocol integrations and onboard new ecosystem players.** Accelerate adoption through strategic partnerships, grants, and incentives that bring new participants onchain. Provide SDKs, documentation, and even a dedicated engineering team to help partners build on the protocol.
* **Accelerate developer adoption of the protocol with Uniswap API.** Pivot the API from a profit-generating product to a zero margin distribution method, expanding the protocol to more platforms and products, including those that previously competed with Labs products. Launch self-serve developer portal for key provisioning and allow integrators to add and rebalance liquidity directly through the API.
* **Drive protocol usage with Labs' interfaces.** Use the interface and wallet to drive more volume to the protocol by making it free, investing heavily in LP UX, and adding new features like dollar-cost-averaging, improved crosschain swaps, gas abstraction, and more.
* **Empower hook builders.** Provide engineering support, routing, support in Labs' interfaces, grants and more.
* **Establish Unichain as a leading liquidity hub.** Optimize Unichain for low-cost, high-performance AMM trading which attracts LPs, asset issuers, and other protocols. Make Uniswap protocol on Unichain the lowest cost place to trade in Labs' interface and API by sponsoring gas.
* **Bring more assets to Uniswap.** Deploy Uniswap protocol wherever new assets live. Build and invest in liquidity bootstrapping tools and token launchers, RWA partnerships and bridging of non-EVM assets to Unichain.

Labs will also accelerate growth through builder programs, grants, incentives, partnerships, M&A, venture, onboarding institutions, and exploring moonshot efforts to unlock new value for the Uniswap ecosystem. We will provide regular updates to the community, including budget reports, frequent product and growth updates, and real-time dashboards giving visibility into our impact.

#### The Growth Budget

We propose governance create an annual growth budget of 20M UNI, distributed quarterly using a [vesting contract](https://github.com/Uniswap/protocol-fees/blob/main/src/UNIVesting.sol) starting January 1, 2026, to fund protocol growth and development.

The growth budget would be governed by a services agreement between Labs and [DUNI](https://gov.uniswap.org/t/governance-proposal-establish-uniswap-governance-as-duni-a-wyoming-duna/25770). This would include an explicit commitment from Labs to maintain alignment between its activities and DUNI, ensuring Labs does not pursue strategies that conflict with token holder interests.

The Foundation will coordinate this process in its role as [Ministerial Agent](https://gov.uniswap.org/t/governance-proposal-establish-uniswap-governance-as-duni-a-wyoming-duna/25770#p-57430-ministerial-agent-agreement-overview-9) to DUNI. If the Snapshot vote passes, an independent committee composed of [Ben Jones](https://x.com/ben_chain?lang=en) and [Hart Lambur](https://x.com/hal2001?lang=en) will be appointed by the Foundation to lead negotiations based on this [draft](https://drive.google.com/file/d/1yXv2fm1XMr1eOsSMzG4DloGzvkFEYc1-/view?usp=sharing) letter of intent, with [Cooley LLP](https://www.cooley.com/) serving as the committee's external counsel. The final negotiated agreement will be included in this governance proposal as part of the full onchain vote, and executed on its passing.

***Update 12/18:***

***Final services agreement between DUNI and Uniswap Labs***

The [final services agreement](https://drive.google.com/file/d/1FxtK846m9CKQ9UqEnBt7uHRRMu9eTifs/view?usp=drive_link) reflects negotiations between the Uniswap Foundation's [independent committee](https://gov.uniswap.org/t/unification-proposal/25881#p-57882-the-growth-budget-13), acting as Ministerial Agent to DUNI, and Uniswap Labs following the temperature check, and does include deviations from the previously posted Letter of Intent.

Hash: 0xb7a5a04f613e49ce4a8c2fb142a37c6781bda05c62d46a782f36bb6e97068d3b

***Indemnification agreements for the independent negotiation committee***

These agreements indemnify the members of the independent negotiation committee ([Hart Lambur](https://drive.google.com/file/d/1kgq66KcAGD5mZzZrW28S8n-XuQS0PH8f/view?usp=drive_link) and [Ben Jones](https://drive.google.com/file/d/18Mp0Honnb3nxGCx0k_aU4wBVncAwDA4F/view?usp=drive_link)), or their respective service providers, as applicable, for the services they provided in negotiating the SPA.

Hashes:
0x96861f436ef11b12dc8df810ab733ea8c7ea16cad6fd476942075ec28d5cf18a (Hart Lambur), 0x576613b871f61f21e14a7caf5970cb9e472e82f993e10e13e2d995703471f011 (Ben Jones)

### Lock the Socks

Unisocks have a long history, ranging between [fun](https://x.com/EthereumFilm/status/1824171012696707244), [fashion](https://x.com/CL207/status/1550155749736689664), [flex](https://x.com/jaysonhobby/status/1382389435329744896), [weird](https://x.com/PleasrDAO/status/1636758148378918917), [weirder](https://x.com/cherdougie/status/1638703664016572419), [even weirder](https://x.com/Snowden/status/1592203313323593731), and gross (we're not linking this one). They were [launched](https://x.com/Uniswap/status/1126506339075641344) by Labs in May 2019 as the first tokenized socks to trade on Uniswap protocol, or anywhere probably.

When Labs launched UNI in September 2020, it [transferred](https://etherscan.io/tx/0xa1c6a16481fe12f2003faa6f5797af8d6ab06512d10bd5010edf63d385c7e449) ownership of the original Uniswap v1 SOCKS/ETH liquidity position to Uniswap governance, where it has sat dormant ever since. We propose that governance move this position from Uniswap v1 on mainnet to Uniswap v4 on Unichain and transfer the LP position to a burn address, locking it forever.

This would ensure that this liquidity can never be withdrawn in the future, permanently locking in the original price curve and realizing the Unisocks vision. Also, the pink socks belong on the pink chain and "Uniswap v4" rhymes with "wore" - which is what you do with socks.

Due to technical complexity, this migration would be executed through a separate onchain vote.

### Thank you

Uniswap protocol wouldn't be here without the LPs, swappers, builders, and community members who've helped the protocol become the largest decentralized exchange in the world. This proposal builds on that foundation, and sets the ecosystem up for the next phase of growth.

Thank you to everyone who has been part of the journey so far. We're just getting started!

**Resources:**

* [Fee documentation](https://github.com/uniswap/protocol-fees)
* [Fee contracts](https://github.com/Uniswap/protocol-fees/tree/main/src)
* [Protocol Fee Discount Auction whitepaper](https://drive.google.com/file/d/1qhZFLTGOOHBx9OZW00dt5DzqEY0C3lhr/view?usp=sharing)
* [Draft letter of intent](https://drive.google.com/file/d/1yXv2fm1XMr1eOsSMzG4DloGzvkFEYc1-/view?usp=sharing)
* [Final services agreement](https://drive.google.com/file/d/1yXv2fm1XMr1eOsSMzG4DloGzvkFEYc1-/view?usp=sharing)
* [Indemnification agreement for Hart Lambur](https://drive.google.com/file/d/1yXv2fm1XMr1eOsSMzG4DloGzvkFEYc1-/view?usp=sharing)
* [Indemnification agreement for Ben Jones](https://drive.google.com/file/d/18Mp0Honnb3nxGCx0k_aU4wBVncAwDA4F/view?usp=drive_link)

## GovernorBravo Proposal Calldata

```
0xda95691a00000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000002e000000000000000000000000000000000000000000000000000000000000005000000000000000000000000000000000000000000000000000000000000000d2000000000000000000000000000000000000000000000000000000000000000080000000000000000000000001f9840a85d5af5bf1d1762f925bdaddc4201f9840000000000000000000000001f98431c8ad98523631ae4a59f267346ea31f98400000000000000000000000018e433c7bf8a2e1d0197ce5d8f9afada1a7713600000000000000000000000005c69bee701ef814a2b6a3edd4b1652cb9cc5aa6f0000000000000000000000001f9840a85d5af5bf1d1762f925bdaddc4201f984000000000000000000000000a1207f3bba224e2c9c3c6d5af63d0eb1582ce587000000000000000000000000a1207f3bba224e2c9c3c6d5af63d0eb1582ce587000000000000000000000000a1207f3bba224e2c9c3c6d5af63d0eb1582ce58700000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000000000000024000000000000000000000000000000000000000000000000000000000000002a0000000000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000004c000000000000000000000000000000000000000000000000000000000000006600000000000000000000000000000000000000000000000000000000000000044a9059cbb000000000000000000000000000000000000000000000000000000000000dead00000000000000000000000000000000000000000052b7d2dcc80cd2e400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002413af40350000000000000000000000005e74c9f42eed283bff3744fbd1889d398d40867d000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024a2e74af60000000000000000000000001a9c8182c09f50c8318d769245bea52c32be35bc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024f46901ed000000000000000000000000f38521f130fccf29db1961597bc5d2b60f995f85000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044095ea7b3000000000000000000000000ca046a83edb78f74ae338bb5a291bf6fdac9e1d20000000000000000000000000000000000000000002116545850052128000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000164f17325e70000000000000000000000000000000000000000000000000000000000000020504f10498bcdb19d4960412dbade6fa1530b8eed65c319f15cbe20fadafe56bd0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000c707467e7fb43fe7cc55264f892dd2d7f8fc27c800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020b7a5a04f613e49ce4a8c2fb142a37c6781bda05c62d46a782f36bb6e97068d3b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000164f17325e70000000000000000000000000000000000000000000000000000000000000020504f10498bcdb19d4960412dbade6fa1530b8eed65c319f15cbe20fadafe56bd000000000000000000000000000000000000000000000000000000000000004000000000000000000000000033a56942fe57f3697fe0ff52ab16cb0ba9b8eadd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002096861f436ef11b12dc8df810ab733ea8c7ea16cad6fd476942075ec28d5cf18a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000164f17325e70000000000000000000000000000000000000000000000000000000000000020504f10498bcdb19d4960412dbade6fa1530b8eed65c319f15cbe20fadafe56bd0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000f9f85a17cc6de9150cd139f64b127976a1de91d100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020576613b871f61f21e14a7caf5970cb9e472e82f993e10e13e2d995703471f01100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000482e2320554e496669636174696f6e0a0a2a5468697320766f746520636f7665727320746865205b554e496669636174696f6e2070726f706f73616c5d2868747470733a2f2f676f762e756e69737761702e6f72672f742f756e696669636174696f6e2d70726f706f73616c2f32353838312920616e6420696e636c75646573207468652066696e616c20636f7079206f66207468652073657276696365732061677265656d656e742c20696e64656d6e696669636174696f6e2061677265656d656e747320666f722074686520696e646570656e64656e74206e65676f74696174696f6e20636f6d6d69747465652c2066696e616c20737065632c20616e6420616e2075706461746564206c697374206f6620763320706f6f6c73207468617420686173206265656e2072656672657368656420746f207265666c65637420746865206c617465737420617661696c61626c6520646174612e205765207265636f6d6d656e642072656164696e67207468652066756c6c2064657461696c73206265666f726520766f74696e672e2a0a0a23232050726f706f73616c20537065630a0a496620746869732070726f706f73616c207061737365732c2069742077696c6c20657865637574652065696768742066756e6374696f6e2063616c6c733a0a0a6060600a2f2f2f204275726e203130306d20554e490a554e492e7472616e73666572283078646561642c203130305f3030305f303030206574686572293b0a0a2f2f2f2053657420746865206f776e6572206f662074686520763320666163746f7279206f6e206d61696e6e657420746f2074686520636f6e666967757265642066656520636f6e74726f6c6c657220746f20656e61626c652076332070726f746f636f6c20666565730a56335f464143544f52592e7365744f776e65722861646472657373287633466565436f6e74726f6c6c657229293b0a0a2f2f2f204368616e67652074686520466565546f53657474657220706172616d65746572206f6e2074686520763220666163746f7279206f6e206d61696e6e657420746f2074686520476f7665726e616e63652054696d656c6f636b0a494f6c645632466565546f5365747465722856325f464143544f52592e666565546f5365747465722829292e736574466565546f5365747465722854494d454c4f434b293b0a0a2f2f2f204368616e67652074686520466565546f20706172616d65746572206f6e2074686520763220666163746f7279206f6e206d61696e6e657420746f20656e61626c652076322070726f746f636f6c20666565730a56325f464143544f52592e736574466565546f286164647265737328746f6b656e4a617229293b0a0a2f2f2f20417070726f76652074776f207965617273206f662076657374696e6720696e746f2074686520554e4956657374657220736d61727420636f6e74726163740a2f2f2f20554e4920737461797320696e20747265617375727920756e74696c2076657374656420616e6420756e76657374656420554e492063616e2062652063616e63656c6c65642062792073657474696e6720617070726f7665206261636b20746f20300a554e492e617070726f7665286164647265737328756e6956657374696e67292c2034305f3030305f303030206574686572293b0a0a2f2f2f2045786563757465207468652073657276696365732061677265656d656e74207769746820556e6973776170204c616273206f6e20626568616c66206f662044554e490a41677265656d656e74416e63686f722e61747465737428616464726573732830784337303734363765376662343346653743633535323634463839324464324437663846633237433829293b0a0a2f2f2f20457865637574652074686520696e64656d6e696669636174696f6e2061677265656d656e7420776974682048617274204c616d627572206f6e20626568616c66206f662044554e490a41677265656d656e74416e63686f722e61747465737428616464726573732830783333413536393432466535376633363937464530664635326142313663623062613962386561646429293b0a0a2f2f2f20457865637574652074686520696e64656d6e696669636174696f6e2061677265656d656e7420776974682044414f204a6f6e6573204c4c43206f6e20626568616c66206f662044554e490a41677265656d656e74416e63686f722e61747465737428616464726573732830784639463835613137634336446539313530436431333966363462313237393736613164453931443129293b0a6060600a0a23232050726f706f73616c0a0a2a48617964656e204164616d732c204b656e204e672c20446576696e2057616c73682a0a0a546f6461792c20556e6973776170204c61627320616e642074686520556e697377617020466f756e646174696f6e20617265206578636974656420746f206d616b652061206a6f696e7420676f7665726e616e63652070726f706f73616c2074686174207475726e73206f6e2070726f746f636f6c206665657320616e6420616c69676e7320696e63656e7469766573206163726f73732074686520556e69737761702065636f73797374656d2c20706f736974696f6e696e672074686520556e69737761702070726f746f636f6c20746f2077696e206173207468652064656661756c7420646563656e7472616c697a65642065786368616e676520666f7220746f6b656e697a65642076616c75652e0a0a5468652070726f746f636f6c206861732070726f636573736564207e2434207472696c6c696f6e20696e20766f6c756d652c206d61646520706f737369626c652062792074686f7573616e6473206f6620646576656c6f706572732c206d696c6c696f6e73206f66206c69717569646974792070726f7669646572732c20616e642068756e6472656473206f66206d696c6c696f6e73206f66207377617070696e672077616c6c6574732e0a0a42757420746865206c617374207365766572616c207965617273206861766520616c736f20636f6d652077697468206f62737461636c65733a20776527766520666f75676874206c6567616c20626174746c657320616e64206e6176696761746564206120686f7374696c6520726567756c61746f727920656e7669726f6e6d656e7420756e6465722047656e736c65722773205345432e205468697320636c696d61746520686173206368616e67656420696e207468652055532c20616e64206d696c6573746f6e6573206c696b6520556e697377617020676f7665726e616e63652061646f7074696e67205b44554e495d2868747470733a2f2f676f762e756e69737761702e6f72672f742f676f7665726e616e63652d70726f706f73616c2d65737461626c6973682d756e69737761702d676f7665726e616e63652d61732d64756e692d612d77796f6d696e672d64756e612f3235373730292c20746865205b44554e415d2868747470733a2f2f6131367a63727970746f2e636f6d2f706f7374732f61727469636c652f64756e612d666f722d64616f732f292c20686176652070726570617265642074686520556e697377617020636f6d6d756e69747920666f7220697473206e6578742073746570732e0a0a546869732070726f706f73616c20636f6d65732061732044654669207265616368657320616e20696e666c656374696f6e20706f696e742e20446563656e7472616c697a65642074726164696e672070726f746f636f6c7320617265205b726976616c696e675d2868747470733a2f2f7777772e746865626c6f636b2e636f2f646174612f646563656e7472616c697a65642d66696e616e63652f6465782d6e6f6e2d637573746f6469616c2f6465782d746f2d6365782d73706f742d74726164652d766f6c756d65292063656e7472616c697a656420706c6174666f726d7320696e20706572666f726d616e636520616e64207363616c652c20746f6b656e732061726520676f696e67206d61696e73747265616d2c20616e6420696e737469747574696f6e7320617265206275696c64696e67206f6e20556e697377617020616e64206f7468657220446546692070726f746f636f6c732e0a0a546869732070726f706f73616c2065737461626c69736865732061206c6f6e672d7465726d206d6f64656c20666f7220686f772074686520556e69737761702065636f73797374656d20776f756c64206f7065726174652c2077686572652070726f746f636f6c2075736167652064726976657320554e49206275726e20616e6420556e6973776170204c61627320666f6375736573206f6e2070726f746f636f6c20646576656c6f706d656e7420616e642067726f7774682e2057652070726f706f736520746f3a0a0a312e205475726e206f6e20556e69737761702070726f746f636f6c206665657320616e6420757365207468657365206665657320746f206275726e20554e490a322e2053656e6420556e69636861696e2073657175656e636572206665657320746f20746869732073616d6520554e49206275726e206d656368616e69736d0a332e204275696c642050726f746f636f6c2046656520446973636f756e742041756374696f6e732028504644412920746f20696e637265617365204c502072657475726e7320616e6420616c6c6f77207468652070726f746f636f6c20746f20696e7465726e616c697a65204d45560a342e204c61756e63682061676772656761746f7220686f
```

