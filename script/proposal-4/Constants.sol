// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// NOTICE: commenting out layer zero and avalanche for now. this will likely be omitted from this
// proposal, but until we are certain, everything is commented out.

/// @dev Throws if any address is the zero address.
function smokeCheck() pure {
  // l1
  require(Ethereum.TIMELOCK != address(0x00), "Ethereum.TIMELOCK is address(0x00)");
  require(Ethereum.UNI != address(0x00), "Ethereum.UNI is address(0x00)");
  require(Ethereum.CELO_PORTAL != address(0x00), "Ethereum.CELO_PORTAL is address(0x00)");
  require(Ethereum.POLYGON_FX_ROOT != address(0x00), "Ethereum.POLYGON_FX_ROOT is address(0x00)");
  require(Ethereum.WORMHOLE_SENDER != address(0x00), "Ethereum.WORMHOLE_SENDER is address(0x00)");
  require(Ethereum.WORMHOLE != address(0x00), "Ethereum.WORMHOLE is address(0x00)");

  // celo
  require(Celo.V2_FACTORY != address(0x00), "Celo.V2_FACTORY is address(0x00)");
  require(Celo.V3_FACTORY != address(0x00), "Celo.V3_FACTORY is address(0x00)");
  require(Celo.V4_POOL_MANAGER != address(0x00), "Celo.V4_POOL_MANAGER is address(0x00)");
  require(Celo.TOKEN_JAR != address(0x00), "Celo.TOKEN_JAR is address(0x00)");
  require(Celo.V3_OPEN_FEE_ADAPTER != address(0x00), "Celo.V3_OPEN_FEE_ADAPTER is address(0x00)");
  require(Celo.UNISWAP_WORMHOLE_MESSAGE_RECEIVER != address(0x00), "Celo.UNISWAP_WORMHOLE_MESSAGE_RECEIVER is address(0x00)");
  require(Celo.CROSS_CHAIN_ACCOUNT != address(0x00), "Celo.CROSS_CHAIN_ACCOUNT is address(0x00)");

  // bnb
  require(BNB.RELEASER_THRESHOLD != 0, "BNB.RELEASER_THRESHOLD is 0");
  require(BNB.V2_FACTORY != address(0x00), "BNB.V2_FACTORY is address(0x00)");
  require(BNB.V3_FACTORY != address(0x00), "BNB.V3_FACTORY is address(0x00)");
  require(BNB.V4_POOL_MANAGER != address(0x00), "BNB.V4_POOL_MANAGER is address(0x00)");
  require(BNB.TOKEN_JAR != address(0x00), "BNB.TOKEN_JAR is address(0x00)");
  require(BNB.V3_OPEN_FEE_ADAPTER != address(0x00), "BNB.V3_OPEN_FEE_ADAPTER is address(0x00)");
  require(BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER != address(0x00), "BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER is address(0x00)");
  require(BNB.WORMHOLE != address(0x00), "BNB.WORMHOLE is address(0x00)");

  // polygon
  require(Polygon.FX_MESSAGE_PROCESSOR != address(0x00), "Polygon.FX_MESSAGE_PROCESSOR is address(0x00)");
  require(Polygon.V2_FACTORY != address(0x00), "Polygon.V2_FACTORY is address(0x00)");
  require(Polygon.V3_FACTORY != address(0x00), "Polygon.V3_FACTORY is address(0x00)");
  require(Polygon.V4_POOL_MANAGER != address(0x00), "Polygon.V4_POOL_MANAGER is address(0x00)");
  require(Polygon.TOKEN_JAR != address(0x00), "Polygon.TOKEN_JAR is address(0x00)");
  require(Polygon.V3_OPEN_FEE_ADAPTER != address(0x00), "Polygon.V3_OPEN_FEE_ADAPTER is address(0x00)");
}

library Ethereum {
  /// @dev Governance Timelock.
  address constant TIMELOCK = 0x1a9C8182C09F50C8318d769245beA52c32BE35BC;

  /// @dev UNI Token.
  address constant UNI = address(0x00);

  /// @dev Celo Optimism Portal.
  address constant CELO_PORTAL = address(0x00);

  /// @dev Polygon FX Root.
  address constant POLYGON_FX_ROOT = address(0x00);

  /// @dev Wormhole Sender.
  address constant WORMHOLE_SENDER = address(0x00);

  /// @dev Wormhole.
  address constant WORMHOLE = address(0x00);
}

library Celo {
  /// @dev Uni V2 Factory.
  ///
  /// source: https://github.com/Uniswap/briefcase/blob/42ce79f148d934ed62523e8cdea18a6886c4f93e/deployments/42220.json#L63
  address constant V2_FACTORY = 0x79a530c8e2fA8748B7B40dd3629C0520c2cCf03f;

  /// @dev Uni V3 Factory.
  ///
  /// source: https://github.com/Uniswap/briefcase/blob/42ce79f148d934ed62523e8cdea18a6886c4f93e/deployments/42220.json#L126
  address constant V3_FACTORY = 0xAfE208a311B21f13EF87E33A90049fC17A7acDEc;

  /// @dev Uni V4 Pool Manager.
  ///
  /// source: https://github.com/Uniswap/briefcase/blob/42ce79f148d934ed62523e8cdea18a6886c4f93e/deployments/42220.json#L39
  address constant V4_POOL_MANAGER = 0x288dc841A52FCA2707c6947B3A777c5E56cd87BC;

  /// @dev Token Jar.
  ///
  /// source: in `script/proposal-3/06_ActivateL2sProposal.s.sol`, otherwise there appears to be no
  /// record of this contract's address.
  address constant TOKEN_JAR = 0x190c22c5085640D1cB60CeC88a4F736Acb59bb6B;

  /// @dev Fee adapter.
  ///
  /// source: in `script/proposal-2/05_ActivateOPBaseArbProposal.s.sol`, otherwise there appears to
  /// be no record of this contract's address.
  address constant V3_OPEN_FEE_ADAPTER = address(0xec23Cf5A1db3dcC6595385D28B2a4D9B52503Be4);

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
  uint256 constant RELEASER_THRESHOLD = 0;

  /// @dev Uni V2 Factory.
  address constant V2_FACTORY = address(0x00);

  /// @dev Uni V3 Factory.
  address constant V3_FACTORY = address(0x00);

  /// @dev Uni V4 Pool Manager.
  address constant V4_POOL_MANAGER = address(0x00);

  /// @dev Token Jar.
  address constant TOKEN_JAR = address(0x00);

  /// @dev Fee adapter.
  address constant V3_OPEN_FEE_ADAPTER = address(0x00);

  /// @dev Wormhole Receiver.
  address constant UNISWAP_WORMHOLE_MESSAGE_RECEIVER = address(0x00);

  /// @dev Wormhole Core Bridge.
  address constant WORMHOLE = address(0x00);
}

library Polygon {
  /// @dev Polygon FX Message Processor.
  address constant FX_MESSAGE_PROCESSOR = address(0x00);

  /// @dev Uni V2 Factory.
  address constant V2_FACTORY = address(0x00);

  /// @dev Uni V3 Factory.
  address constant V3_FACTORY = address(0x00);

  /// @dev Uni V4 Pool Manager.
  address constant V4_POOL_MANAGER = address(0x00);

  /// @dev Token Jar.
  address constant TOKEN_JAR = address(0x00);

  /// @dev Fee adapter.
  address constant V3_OPEN_FEE_ADAPTER = address(0x00);

  /// @dev Wormhole Core Bridge.
  address constant WORMHOLE = address(0x00);
}

/// @dev Wormhole-defined chain Id's. Different from real chain Id's.
library Wormhole {
  uint16 internal constant ETH_CHAIN_ID = 2;

  uint16 internal constant CELO_CHAIN_ID = 14;

  uint16 internal constant BNB_CHAIN_ID = 4;

  uint16 internal constant POLYGON_CHAIN_ID = 5;
}
