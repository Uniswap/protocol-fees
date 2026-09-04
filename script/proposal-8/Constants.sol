// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

// -------------------------------------------------------------------------------------------------
// Uniswap Earn
//
/// @dev Uniswap Earn vaults on Ethereum. Each is a Morpho `VaultV2` owned by the Timelock.
/// @dev Structured to make it easy to add to govkit once this proposal is executed.
struct Earn {
  address uniUSDC;
  address uniUSDT;
  address uniETH;
}

library LibEarn {
  function loadLatest() internal pure returns (Earn memory) {
    return Earn({
      uniUSDC: 0x5B453493D2328E7F747eb2e66446eFe707728be7,
      uniUSDT: 0xb8274eFADB953FE9ae052D481a3FC5B6A3ceD703,
      uniETH: 0x98D2b241DA14c5dd848812708Eb8A1F3c5512f9d
    });
  }
}

// -------------------------------------------------------------------------------------------------
// Proposal parameters
//
/// @dev Sentinels this proposal adds and removes. Supplied by Gauntlet.
library Sentinels {
  address constant UNI_USDC_NEW = 0xF66b884D1906F37c1692CEa63564316FF975Cd75;
  address constant UNI_USDC_LEGACY = 0xc3FE37DB03B5720D1684bE2e0200E0Af07853Ad9;

  address constant UNI_USDT_NEW = 0xD9b023059dfD00C2DC68C4d8d0c70BCaA30577Db;
  address constant UNI_USDT_LEGACY = 0x2745513325d4Ce5724e5B6Fb663356C427AfdeCc;

  address constant UNI_ETH_NEW = 0x4Ff315B873d6e5Ad8ff7fF3e17D340862762cc2f;
  address constant UNI_ETH_LEGACY = 0xc63A00De30AeB5666a8aC3478a4D119D38058c7E;
}
