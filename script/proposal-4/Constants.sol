// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// NOTICE: commenting out layer zero and avalanche for now. this will likely be omitted from this
// proposal, but until we are certain, everything is commented out.

/// @dev Throws if any address is the zero address.
function smokeCheck() pure {
  // l1
  require(L1.TIMELOCK != address(0x00), "L1.TIMELOCK is address(0x00)");
  require(L1.UNI != address(0x00), "L1.UNI is address(0x00)");
  require(L1.CELO_PORTAL != address(0x00), "L1.CELO_PORTAL is address(0x00)");
  require(L1.POLYGON_FX_ROOT != address(0x00), "L1.POLYGON_FX_ROOT is address(0x00)");
  require(L1.WORMHOLE_SENDER != address(0x00), "L1.WORMHOLE_SENDER is address(0x00)");
  require(L1.WORMHOLE != address(0x00), "L1.WORMHOLE is address(0x00)");
  // require(L1.LAYER_ZERO_ENDPOINT != address(0x00));

  // celo
  require(Celo.V2_FACTORY != address(0x00), "Celo.V2_FACTORY is address(0x00)");
  require(Celo.V3_FACTORY != address(0x00), "Celo.V3_FACTORY is address(0x00)");
  require(Celo.V4_POOL_MANAGER != address(0x00), "Celo.V4_POOL_MANAGER is address(0x00)");
  require(Celo.TOKEN_JAR != address(0x00), "Celo.TOKEN_JAR is address(0x00)");
  require(Celo.WORMHOLE_RECEIVER != address(0x00), "Celo.WORMHOLE_RECEIVER is address(0x00)");

  // polygon
  require(Polygon.FX_CHILD != address(0x00), "Polygon.FX_CHILD is address(0x00)");
  require(Polygon.V2_FACTORY != address(0x00), "Polygon.V2_FACTORY is address(0x00)");
  require(Polygon.V3_FACTORY != address(0x00), "Polygon.V3_FACTORY is address(0x00)");
  require(Polygon.V4_POOL_MANAGER != address(0x00), "Polygon.V4_POOL_MANAGER is address(0x00)");
  require(Polygon.TOKEN_JAR != address(0x00), "Polygon.TOKEN_JAR is address(0x00)");

  // bnb
  require(BNB.V2_FACTORY != address(0x00), "BNB.V2_FACTORY is address(0x00)");
  require(BNB.V3_FACTORY != address(0x00), "BNB.V3_FACTORY is address(0x00)");
  require(BNB.V4_POOL_MANAGER != address(0x00), "BNB.V4_POOL_MANAGER is address(0x00)");
  require(BNB.TOKEN_JAR != address(0x00), "BNB.TOKEN_JAR is address(0x00)");
  require(BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER != address(0x00), "BNB.UNISWAP_WORMHOLE_MESSAGE_RECEIVER is address(0x00)");
  require(BNB.WORMHOLE != address(0x00), "BNB.WORMHOLE is address(0x00)");

  // // avalanche
  // require(Avalanche.V2_FACTORY != address(0x00));
  // require(Avalanche.V3_FACTORY != address(0x00));
  // require(Avalanche.V4_POOL_MANAGER != address(0x00));
  // require(Avalanche.TOKEN_JAR != address(0x00));
  // require(Avalanche.OMNICHAIN_GOVERNANCE != address(0x00));
}

library L1 {
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

  // /// @dev Layer Zero Endpoint.
  // address constant LAYER_ZERO_ENDPOINT = address(0x00);
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
  /// source: in `script/proposal-03/06_ActivateL2sProposal.s.sol`, otherwise there appears to be no
  /// record of this contract's address.
  address constant TOKEN_JAR = 0x190c22c5085640D1cB60CeC88a4F736Acb59bb6B;

  /// @dev Wormhole Receiver.
  /// source: protocol is owned by this at the time of writing.
  /// V2Factory: `cast call 0x79a530c8e2fA8748B7B40dd3629C0520c2cCf03f "feeToSetter()"`
  /// V3Factory: `cast call 0xAfE208a311B21f13EF87E33A90049fC17A7acDEc "owner()"`
  /// PoolManager: `cast call 0x288dc841A52FCA2707c6947B3A777c5E56cd87BC "owner()"`
  address constant WORMHOLE_RECEIVER = 0x0Eb863541278308c3A64F8E908BC646e27BFD071;
}

library Polygon {
  /// @dev Polygon FX Child.
  address constant FX_CHILD = address(0x00);

  /// @dev Uni V2 Factory.
  address constant V2_FACTORY = address(0x00);

  /// @dev Uni V3 Factory.
  address constant V3_FACTORY = address(0x00);

  /// @dev Uni V4 Pool Manager.
  address constant V4_POOL_MANAGER = address(0x00);

  /// @dev Token Jar.
  address constant TOKEN_JAR = address(0x00);
}

library BNB {
  /// @dev Uni V2 Factory.
  address constant V2_FACTORY = address(0x00);

  /// @dev Uni V3 Factory.
  address constant V3_FACTORY = address(0x00);

  /// @dev Uni V4 Pool Manager.
  address constant V4_POOL_MANAGER = address(0x00);

  /// @dev Token Jar.
  address constant TOKEN_JAR = address(0x00);

  /// @dev Wormhole Receiver.
  address constant UNISWAP_WORMHOLE_MESSAGE_RECEIVER = address(0x00);

  /// @dev Wormhole Core Bridge.
  address constant WORMHOLE = address(0x00);
}

// library Avalanche {
//   /// @dev Uni V2 Factory.
//   address constant V2_FACTORY = address(0x00);

//   /// @dev Uni V3 Factory.
//   address constant V3_FACTORY = address(0x00);

//   /// @dev Uni V4 Pool Manager.
//   address constant V4_POOL_MANAGER = address(0x00);

//   /// @dev Token Jar.
//   address constant TOKEN_JAR = address(0x00);

//   /// @dev Omnichain Governance.
//   address constant OMNICHAIN_GOVERNANCE = address(0x00);
// }

library Wormhole {
  uint16 internal constant ETH_CHAIN_ID = 2;

  uint16 internal constant CELO_CHAIN_ID = 14;

  uint16 internal constant BNB_CHAIN_ID = 4;
}

// library LayerZero {
//   uint16 internal constant AVALANCHE_CHAIN_ID = 30106;
// }
