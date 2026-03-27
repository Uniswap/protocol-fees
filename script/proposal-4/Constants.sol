// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Throws if any address is the zero address.
function vibeCheck() pure {
  // l1
  require(L1.GOVERNOR != address(0x00));
  require(L1.CELO_PORTAL != address(0x00));
  require(L1.POLYGON_FX_ROOT != address(0x00));
  require(L1.WORMHOLE_SENDER != address(0x00));
  require(L1.LAYER_ZERO_ENDPOINT != address(0x00));

  // celo
  require(Celo.V2_FACTORY != address(0x00));
  require(Celo.V3_FACTORY != address(0x00));
  require(Celo.V4_POOL_MANAGER != address(0x00));
  require(Celo.TOKEN_JAR != address(0x00));
  require(Celo.WORMHOLE_RECEIVER != address(0x00));

  // polygon
  require(Polygon.FX_CHILD != address(0x00));
  require(Polygon.V2_FACTORY != address(0x00));
  require(Polygon.V3_FACTORY != address(0x00));
  require(Polygon.V4_POOL_MANAGER != address(0x00));
  require(Polygon.TOKEN_JAR != address(0x00));

  // bnb
  require(BNB.V2_FACTORY != address(0x00));
  require(BNB.V3_FACTORY != address(0x00));
  require(BNB.V4_POOL_MANAGER != address(0x00));
  require(BNB.TOKEN_JAR != address(0x00));
  require(BNB.WORMHOLE_RECEIVER != address(0x00));

  // avalanche
  require(Avalanche.V2_FACTORY != address(0x00));
  require(Avalanche.V3_FACTORY != address(0x00));
  require(Avalanche.V4_POOL_MANAGER != address(0x00));
  require(Avalanche.TOKEN_JAR != address(0x00));
  require(Avalanche.OMNICHAIN_GOVERNANCE != address(0x00));
}

library L1 {
  /// @dev Governor.
  address constant GOVERNOR = 0x408ED6354d4973f66138C91495F2f2FCbd8724C3;

  /// @dev Celo Optimism Portal.
  address constant CELO_PORTAL = address(0x00);

  /// @dev Polygon FX Root.
  address constant POLYGON_FX_ROOT = address(0x00);

  /// @dev Wormhole Sender.
  address constant WORMHOLE_SENDER = address(0x00);

  /// @dev Layer Zero Endpoint.
  address constant LAYER_ZERO_ENDPOINT = address(0x00);
}

library Celo {
  /// @dev Uni V2 Factory.
  address constant V2_FACTORY = address(0x00);

  /// @dev Uni V3 Factory.
  address constant V3_FACTORY = address(0x00);

  /// @dev Uni V4 Pool Manager.
  address constant V4_POOL_MANAGER = address(0x00);

  /// @dev Token Jar.
  address constant TOKEN_JAR = address(0x00);

  /// @dev Wormhole Receiver.
  address constant WORMHOLE_RECEIVER = address(0x00);
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
  address constant WORMHOLE_RECEIVER = address(0x00);
}

library Avalanche {
  /// @dev Uni V2 Factory.
  address constant V2_FACTORY = address(0x00);

  /// @dev Uni V3 Factory.
  address constant V3_FACTORY = address(0x00);

  /// @dev Uni V4 Pool Manager.
  address constant V4_POOL_MANAGER = address(0x00);

  /// @dev Token Jar.
  address constant TOKEN_JAR = address(0x00);

  /// @dev Omnichain Governance.
  address constant OMNICHAIN_GOVERNANCE = address(0x00);
}

library Wormhole {
  uint16 internal constant CELO_CHAIN_ID = 14;

  uint16 internal constant BNB_CHAIN_ID = 4;
}

library LayerZero {
  uint16 internal constant AVALANCHE_CHAIN_ID = 30106;
}
