// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// NOTICE: commenting out layer zero and avalanche for now. this will likely be omitted from this
// proposal, but until we are certain, everything is commented out.

/// @dev Throws if any address is the zero address.
function smokeCheck() pure {
  // l1
  require(Ethereum.TIMELOCK != address(0x00), "Ethereum.TIMELOCK is address(0x00)");
  require(Ethereum.GOVERNOR_BRAVO != address(0x00), "Ethereum.GOVERNOR_BRAVO is address(0x00)");
  require(Ethereum.UNI != address(0x00), "Ethereum.UNI is address(0x00)");
  require(Ethereum.POLYGON_FX_ROOT != address(0x00), "Ethereum.POLYGON_FX_ROOT is address(0x00)");
  require(Ethereum.WORMHOLE_SENDER != address(0x00), "Ethereum.WORMHOLE_SENDER is address(0x00)");
  require(Ethereum.WORMHOLE != address(0x00), "Ethereum.WORMHOLE is address(0x00)");

  // celo
  require(Celo.V2_FACTORY != address(0x00), "Celo.V2_FACTORY is address(0x00)");
  require(Celo.V3_FACTORY != address(0x00), "Celo.V3_FACTORY is address(0x00)");
  require(Celo.V4_POOL_MANAGER != address(0x00), "Celo.V4_POOL_MANAGER is address(0x00)");
  require(Celo.TOKEN_JAR != address(0x00), "Celo.TOKEN_JAR is address(0x00)");
  require(Celo.V3_OPEN_FEE_ADAPTER != address(0x00), "Celo.V3_OPEN_FEE_ADAPTER is address(0x00)");
  require(
    Celo.UNISWAP_WORMHOLE_MESSAGE_RECEIVER != address(0x00),
    "Celo.UNISWAP_WORMHOLE_MESSAGE_RECEIVER is address(0x00)"
  );
  require(Celo.CROSS_CHAIN_ACCOUNT != address(0x00), "Celo.CROSS_CHAIN_ACCOUNT is address(0x00)");

  // bnb
  require(BNB.RELEASER_THRESHOLD != 0, "BNB.RELEASER_THRESHOLD is 0");
  require(BNB.V2_FACTORY != address(0x00), "BNB.V2_FACTORY is address(0x00)");
  require(BNB.V3_FACTORY != address(0x00), "BNB.V3_FACTORY is address(0x00)");
  require(BNB.V4_POOL_MANAGER != address(0x00), "BNB.V4_POOL_MANAGER is address(0x00)");
  require(
    BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER != address(0x00),
    "BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER is address(0x00)"
  );
  require(BNB.WORMHOLE != address(0x00), "BNB.WORMHOLE is address(0x00)");

  // polygon
  require(Polygon.RELEASER_THRESHOLD != 0, "Polygon.RELEASER_THRESHOLD is 0");
  require(Polygon.ETHEREUM_PROXY != address(0x00), "Polygon.ETHEREUM_PROXY is address(0x00)");
  require(Polygon.V2_FACTORY != address(0x00), "Polygon.V2_FACTORY is address(0x00)");
  require(Polygon.V3_FACTORY != address(0x00), "Polygon.V3_FACTORY is address(0x00)");
  require(Polygon.V4_POOL_MANAGER != address(0x00), "Polygon.V4_POOL_MANAGER is address(0x00)");
  require(Polygon.WORMHOLE != address(0x00), "Polygon.WORMHOLE is address(0x00)");
}

library Ethereum {
  /// @dev Governance Timelock.
  ///
  /// source: protocol owned by this:
  /// V2Factory: `cast call 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f "feeToSetter()(address)"`
  /// OpenFeeAdapter (owns V3Factory): cast call 0xf2371551Fe3937Db7c750f4DfABe5c2fFFdcBf5A
  /// "owner()(address)" PoolManager: `cast call 0x000000000004444c5dc75cB358380D2e3dE08A90
  /// "owner()(address)"`
  /// GovernorBravo: `cast call 0x408ED6354d4973f66138C91495F2f2FCbd8724C3 "admin()(address)"`
  address constant TIMELOCK = 0x1a9C8182C09F50C8318d769245beA52c32BE35BC;

  /// @dev Governor Bravo. Receives proposals via `propose`; the Timelock executes them after the
  /// queued delay.
  ///
  /// source: owns Timelock: `cast call 0x1a9C8182C09F50C8318d769245beA52c32BE35BC
  /// "admin()(address)"`
  address constant GOVERNOR_BRAVO = address(0x408ED6354d4973f66138C91495F2f2FCbd8724C3);

  /// @dev UNI Token.
  ///
  /// source: designated by GovernorBravo: `cast call 0x408ED6354d4973f66138C91495F2f2FCbd8724C3
  /// "uni()(address)"`
  address constant UNI = address(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);

  /// @dev Polygon FX Root.
  ///
  /// source: https://github.com/0xPolygon/fx-portal#deployment-addresses
  address constant POLYGON_FX_ROOT = address(0xfe5e5D361b2ad62c541bAb87C45a0B9B018389a2);

  /// @dev Wormhole Sender.
  ///
  /// source: owned by Timelock, used in prev scripts
  /// Timelock: `cast call 0xf5F4496219F31CDCBa6130B5402873624585615a "owner()(address)"`
  /// script: `script/proposal-2/05_ActivateL2sProposal.s.sol`
  address constant WORMHOLE_SENDER = address(0xf5F4496219F31CDCBa6130B5402873624585615a);

  /// @dev Wormhole.
  ///
  /// source: immutable constructor arg to WORMHOLE_SENDER, listed in wormhole docs:
  /// docs: https://wormhole.com/docs/products/reference/contract-addresses/#core-contracts
  /// cosntructor arg (private immutable):
  /// https://etherscan.io/tx/0xcf516bddc8bffb979ae73c48a30cbce4612fc821795bf771f486189cf962f295
  address constant WORMHOLE = address(0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B);
}

library Celo {
  /// @dev Uni V2 Factory.
  ///
  /// source: Governance-assigned ENS record (42220)
  /// https://app.ens.domains/v2deployments.uniswap.eth?tab=records
  address constant V2_FACTORY = 0x114A43DF6C5f54EBB8A9d70Cd1951D3dD68004c7;

  /// @dev Uni V3 Factory.
  ///
  /// source:
  /// https://github.com/Uniswap/briefcase/blob/42ce79f148d934ed62523e8cdea18a6886c4f93e/deployments/42220.json#L126
  address constant V3_FACTORY = 0xAfE208a311B21f13EF87E33A90049fC17A7acDEc;

  /// @dev Uni V4 Pool Manager.
  ///
  /// source:
  /// https://github.com/Uniswap/briefcase/blob/42ce79f148d934ed62523e8cdea18a6886c4f93e/deployments/42220.json#L39
  address constant V4_POOL_MANAGER = 0x288dc841A52FCA2707c6947B3A777c5E56cd87BC;

  /// @dev Token Jar.
  ///
  /// source: in `script/proposal-3/06_ActivateL2sProposal.s.sol`, otherwise there appears to be no
  /// record of this contract's address.
  address constant TOKEN_JAR = 0x190c22c5085640D1cB60CeC88a4F736Acb59bb6B;

  /// @dev Fee adapter.
  ///
  /// source: in `script/proposal-2/06_ActivateL2sProposal.s.sol`, otherwise there appears to
  /// be no record of this contract's address.
  address constant V3_OPEN_FEE_ADAPTER = address(0xB9952C01830306ea2fAAe1505f6539BD260Bfc48);

  /// @dev Wormhole Receiver.
  ///
  /// source: protocol is owned by this at the time of writing.
  /// V2Factory: `cast call 0x79a530c8e2fA8748B7B40dd3629C0520c2cCf03f "feeToSetter()"`
  /// V3Factory: `cast call 0xAfE208a311B21f13EF87E33A90049fC17A7acDEc "owner()"`
  /// PoolManager: `cast call 0x288dc841A52FCA2707c6947B3A777c5E56cd87BC "owner()"`
  address constant UNISWAP_WORMHOLE_MESSAGE_RECEIVER = 0x0Eb863541278308c3A64F8E908BC646e27BFD071;

  /// @dev Optimism Bridge Cross Chain Account
  ///
  /// source: referenced in last two proposals for ownership handoff:
  /// - `script/proposal-2/05_ActivateL2sProposal.s.sol`
  /// - `script/proposal-3/06_ActivateL2sProposal.s.sol`
  address constant CROSS_CHAIN_ACCOUNT = address(0x044aAF330d7fD6AE683EEc5c1C1d1fFf5196B6b7);
}

library BNB {
  uint256 constant RELEASER_THRESHOLD = 4000e18;

  /// @dev Uni V2 Factory.
  ///
  /// source:
  /// https://github.com/Uniswap/briefcase/blob/42ce79f148d934ed62523e8cdea18a6886c4f93e/deployments/56.json#L87
  address constant V2_FACTORY = address(0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6);

  /// @dev Uni V3 Factory.
  ///
  /// source: governance-assigned ens record (56)
  /// https://app.ens.domains/v2deployments.uniswap.eth?tab=records
  address constant V3_FACTORY = address(0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7);

  /// @dev Uni V4 Pool Manager.
  ///
  /// source:
  /// https://github.com/Uniswap/briefcase/blob/42ce79f148d934ed62523e8cdea18a6886c4f93e/deployments/56.json#L18
  address constant V4_POOL_MANAGER = address(0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF);

  /// @dev Wormhole Receiver.
  ///
  /// source: owns the protocol:
  /// V2Factory: `cast call 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6 "feeToSetter()(address)"`
  /// V3Factory: cast call 0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7 "owner()(address)"
  /// PoolManager: `cast call 0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF "owner()(address)"`
  address constant UNISWAP_WORMHOLE_MESSAGE_RECEIVER =
    address(0x341c1511141022cf8eE20824Ae0fFA3491F1302b);

  /// @dev Wormhole Core Bridge.
  ///
  /// source: immutable constructor arg to UNISWAP_WORMHOLE_MESSAGE_RECEIVER, linked in docs
  /// cosntructor arg (private immutable):
  /// https://bscscan.com/tx/0x4be120ae0b43fc5264d2de953947049d7a420f997fb11b9e04d66ec7b6b5339b
  /// note; it's the same as the one on ethereum
  address constant WORMHOLE = address(0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B);
}

library Polygon {
  uint256 constant RELEASER_THRESHOLD = 2000e18;

  /// @dev Polygon-side governance receiver
  ///
  /// source: owns the protocol:
  /// V2Factory: `cast call 0x9e5A52f57b3038F1B8EeE45F28b3C1967e22799C "feeToSetter()(address)"`
  /// V3Factory: `cast call 0x1F98431c8aD98523631AE4a59f267346ea31F984 "owner()(address)"`
  /// PoolManager: `cast call 0x67366782805870060151383f4bbff9dab53e5cd6 "owner()(address)"`
  address constant ETHEREUM_PROXY = address(0x8a1B966aC46F42275860f905dbC75EfBfDC12374);

  /// @dev Uni V2 Factory.
  ///
  /// source:
  /// https://github.com/Uniswap/briefcase/blob/42ce79f148d934ed62523e8cdea18a6886c4f93e/deployments/137.json#L80
  address constant V2_FACTORY = address(0x9e5A52f57b3038F1B8EeE45F28b3C1967e22799C);

  /// @dev Uni V3 Factory.
  ///
  /// source:
  /// https://github.com/Uniswap/briefcase/blob/42ce79f148d934ed62523e8cdea18a6886c4f93e/deployments/137.json#L149
  address constant V3_FACTORY = address(0x1F98431c8aD98523631AE4a59f267346ea31F984);

  /// @dev Uni V4 Pool Manager.
  ///
  /// source:
  /// https://github.com/Uniswap/briefcase/blob/42ce79f148d934ed62523e8cdea18a6886c4f93e/deployments/137.json#L11
  address constant V4_POOL_MANAGER = address(0x67366782805870060151383F4BbFF9daB53e5cD6);

  /// @dev Wormhole Core Bridge.
  ///
  /// source: https://wormhole.com/docs/products/reference/contract-addresses/
  address constant WORMHOLE = address(0x7A4B5a56256163F07b2C80A7cA55aBE66c4ec4d7);
}

/// @dev Wormhole-defined chain Id's. Different from real chain Id's.
library Wormhole {
  uint16 internal constant ETH_CHAIN_ID = 2;

  uint16 internal constant CELO_CHAIN_ID = 14;

  uint16 internal constant BNB_CHAIN_ID = 4;

  uint16 internal constant POLYGON_CHAIN_ID = 5;
}
