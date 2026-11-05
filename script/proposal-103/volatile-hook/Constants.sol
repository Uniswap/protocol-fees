// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

// -------------------------------------------------------------------------------------------------
// VolatilePairHook upgrade parameters

/// @dev Ethereum parameters of the VolatilePairHook upgrade.
library VolatileHook {
  /// @dev The hook's ERC1967 proxy, the registered v4 hook. The upgrade keeps this address.
  ///      https://etherscan.io/address/0x000022Ec4eBD6b12294396E852E4C3876b253Cc0
  address constant PROXY = 0x000022Ec4eBD6b12294396E852E4C3876b253Cc0;

  /// @dev The implementation the proxy runs before the upgrade, built from `v4-hooks-public` commit
  ///      a053a88.
  ///      https://etherscan.io/address/0x1DDbf7215be4F8A7623B9B1B0255C6e1E3F6c000
  address constant CURRENT_IMPLEMENTATION = 0x1DDbf7215be4F8A7623B9B1B0255C6e1E3F6c000;

  /// @dev The implementation the proposal installs, built from `v4-hooks-public` PR 87.
  // TODO: replace the placeholder with the implementation's address once it is deployed on Ethereum.
  address constant NEW_IMPLEMENTATION = address(0xBEEF);

  /// @dev The new implementation's `maxTempFeeBlockGap` on Ethereum, from PR 87's deploy
  /// parameters: the temporary fee applies only on the block right after the previous block open.
  uint256 constant MAX_TEMP_FEE_BLOCK_GAP = 1;
}

/// @dev Asserts every upgrade parameter is set.
function smokeCheck() pure {
  require(VolatileHook.NEW_IMPLEMENTATION != address(0), "VolatileHook.NEW_IMPLEMENTATION unset");
  require(VolatileHook.MAX_TEMP_FEE_BLOCK_GAP != 0, "VolatileHook.MAX_TEMP_FEE_BLOCK_GAP unset");
}
