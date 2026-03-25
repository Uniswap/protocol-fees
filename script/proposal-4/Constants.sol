// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Throws if any address is the zero address.
function vibeCheck() pure {
    // l1
    require(L1.GOVERNOR != address(0x00));
    require(L1.CELO_PORTAL != address(0x00));
    require(L1.POLYGON_SENDER != address(0x00));
    require(L1.ZK_SYNC_HUB != address(0x00));

    // celo
    require(Celo.V2_FACTORY != address(0x00));
    require(Celo.V3_FACTORY != address(0x00));
    require(Celo.TOKEN_JAR != address(0x00));

    // polygon
    require(Polygon.STATE_SYNC != address(0x00));
    require(Polygon.V2_FACTORY != address(0x00));
    require(Polygon.V3_FACTORY != address(0x00));
    require(Polygon.TOKEN_JAR != address(0x00));

    // zksync
    require(ZkSync.ZK_SYNC_ERA_ID != 0x00);
    require(ZkSync.V2_FACTORY != address(0x00));
    require(ZkSync.V3_FACTORY != address(0x00));
    require(ZkSync.TOKEN_JAR != address(0x00));
}

library L1 {
    /// @dev Governor.
    address constant GOVERNOR = 0x408ED6354d4973f66138C91495F2f2FCbd8724C3;

    /// @dev Celo Optimism Portal.
    address constant CELO_PORTAL = address(0x00);

    /// @dev Polygon Sender.
    /// @dev TODO: deploy this.
    address constant POLYGON_SENDER = address(0x00);

    /// @dev ZkSync Bridge Hub.
    address constant ZK_SYNC_HUB = address(0x00);
}

library Celo {
    /// @dev Uni V2 Factory.
    address constant V2_FACTORY = address(0x00);

    /// @dev Uni V3 Factory.
    address constant V3_FACTORY = address(0x00);

    /// @dev Token Jar.
    address constant TOKEN_JAR = address(0x00);
}

library Polygon {
    /// @dev Polygon StateSync.
    address constant STATE_SYNC = address(0x1001);

    /// @dev Uni V2 Factory.
    address constant V2_FACTORY = address(0x00);

    /// @dev Uni V3 Factory.
    address constant V3_FACTORY = address(0x00);

    /// @dev Token Jar.
    address constant TOKEN_JAR = address(0x00);
}

library ZkSync {
    /// @dev ZkSync Era Chain ID (NOT CANNON CHAIN ID).
    /// @dev TODO: check this, claude quoted this.
    uint256 constant ZK_SYNC_ERA_ID = 324;

    /// @dev Uni V2 Factory.
    address constant V2_FACTORY = address(0x00);

    /// @dev Uni V3 Factory.
    address constant V3_FACTORY = address(0x00);

    /// @dev Token Jar.
    address constant TOKEN_JAR = address(0x00);
}
