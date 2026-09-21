// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

library Earn {
  address constant UNI_USDC = 0x5B453493D2328E7F747eb2e66446eFe707728be7;
  address constant UNI_USDT = 0xb8274eFADB953FE9ae052D481a3FC5B6A3ceD703;
  address constant UNI_ETH = 0x98D2b241DA14c5dd848812708Eb8A1F3c5512f9d;
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

/// @dev Asserts every new sentinel is set. `preflight()` proves each legacy sentinel against the
///      vault, but any address passes its `!isSentinel` check on the new one, so a zero here would
///      reach the proposal.
function smokeCheck() pure {
  require(Sentinels.UNI_USDC_NEW != address(0), "Sentinels.UNI_USDC_NEW unset");
  require(Sentinels.UNI_USDT_NEW != address(0), "Sentinels.UNI_USDT_NEW unset");
  require(Sentinels.UNI_ETH_NEW != address(0), "Sentinels.UNI_ETH_NEW unset");
}
