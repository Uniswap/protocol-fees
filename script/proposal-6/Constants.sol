// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

library V4FeeController {
  address constant Ethereum = address(0x00);
  address constant Arbitrum = address(0x00);
  address constant Base = address(0x00);
  address constant Celo = address(0x00);
  address constant Optimism = address(0x00);
  address constant Soneium = address(0x00);
  address constant XLayer = address(0x00);
  address constant WorldChain = address(0x00);
  address constant Zora = address(0x00);
  address constant BNBChain = address(0x00);
  address constant Polygon = address(0x00);

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
