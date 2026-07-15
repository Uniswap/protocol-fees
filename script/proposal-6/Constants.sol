// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

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
