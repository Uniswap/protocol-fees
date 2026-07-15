// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

library V4FeeController {
  address constant Ethereum = address(0x00);
  address constant Base = address(0x00);
  address constant Robinhood = address(0x00);
  address constant BNBChain = address(0x00);
  address constant Arbitrum = address(0x00);
  address constant Optimism = address(0x00);
  address constant Polygon = address(0x00);

  address constant Celo = address(0x00);
  address constant Soneium = address(0x00);
  address constant XLayer = address(0x00);
  address constant WorldChain = address(0x00);
  address constant Zora = address(0x00);

  function smokeCheck() internal pure {
    require(Ethereum != address(0x00), "Ethereum is not set.");
    require(Arbitrum != address(0x00), "Arbitrum is not set.");
    require(Base != address(0x00), "Base is not set.");
    require(Celo != address(0x00), "Celo is not set.");
    require(Optimism != address(0x00), "Optimism is not set.");
    require(Soneium != address(0x00), "Soneium is not set.");
    require(XLayer != address(0x00), "XLayer is not set.");
    require(WorldChain != address(0x00), "Worldchain is not set.");
    require(Zora != address(0x00), "Zora is not set.");
    require(BNBChain != address(0x00), "BNBChain is not set.");
    require(Polygon != address(0x00), "Polygon is not set.");
  }
}

library Ethereum {
  address constant RH_L1_ERC20_GATEWAY = 0x85001CC4867C5e1C22dA4B79BB8852B9e2a06da0;
  address constant RH_INBOX = 0x1A07cc4BD17E0118BdB54D70990D2158AbAD7a2D;
}

library Robinhood {
  uint256 constant CHAIN_ID = 4663;

  address constant V2_FACTORY = 0x8bcEaA40B9AcdfAedF85AdF4FF01F5Ad6517937f;
  address constant V3_FACTORY = 0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;
  address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
  address constant UNI = 0x4540A3483Bb94827b0FD9c2b16a6A35Dd6F23529;
  address constant TOKEN_JAR = address(0x00);
  address constant L2_GATEWAY_ROUTER = 0x1E324B9316138CA9a73F960213621AD1aaf01B89;
}
