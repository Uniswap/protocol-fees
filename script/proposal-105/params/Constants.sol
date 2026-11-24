// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Uniswap} from "govkit/types/Uniswap.sol";
import {ChainId} from "govkit/constants/ChainId.sol";

import {IV3OpenFeeAdapter} from "../../../src/interfaces/IV3OpenFeeAdapter.sol";

// -------------------------------------------------------------------------------------------------
// Proposal 105 parameters
//
// The policy and rulesets are proposal 104's; see `../../proposal-104/params/Constants.sol`.

/// @dev Record file shared by the prerequisite script and the proposal, at
///      `.records/<RECORD_NAME>.json`.
string constant RECORD_NAME = "Proposal105";

/// @dev Per-chain policy parameters, in the format `PolicyParams.sol` in proposal 104 describes.
///      Celo's `currencyIds` are those of its v1 `V4FeePolicy`, which proposal 6 deployed but never
///      connected to the PoolManager.
string constant POLICY_PARAMS_JSON = "script/proposal-105/params/v4-fee-policy.json";

/// @dev Record key of the `V4FeeAdapter`. The policy and rulesets use proposal 104's keys.
string constant V4_FEE_ADAPTER_RECORD = "V4FeeAdapter";

/// @dev Returns the TokenJar that the new `V4FeeAdapter` on `chainId` sends fees to. Run on
///      `chainId`. Reverts unless the chain's `V3OpenFeeAdapter` sends its fees to the same
///      TokenJar, so a wrong entry here cannot become the adapter's immutable fee destination.
function tokenJar(Uniswap storage uniswap, uint256 chainId) view returns (address jar) {
  address v3Adapter;
  if (chainId == ChainId.Celo) {
    (jar, v3Adapter) = (uniswap.celo.tokenJar, uniswap.celo.v3OpenFeeAdapter);
  } else if (chainId == ChainId.Soneium) {
    (jar, v3Adapter) = (uniswap.soneium.tokenJar, uniswap.soneium.v3OpenFeeAdapter);
  } else if (chainId == ChainId.WorldChain) {
    (jar, v3Adapter) = (uniswap.worldChain.tokenJar, uniswap.worldChain.v3OpenFeeAdapter);
  } else if (chainId == ChainId.XLayer) {
    (jar, v3Adapter) = (uniswap.xLayer.tokenJar, uniswap.xLayer.v3OpenFeeAdapter);
  } else if (chainId == ChainId.Zora) {
    (jar, v3Adapter) = (uniswap.zora.tokenJar, uniswap.zora.v3OpenFeeAdapter);
  } else {
    revert("no TokenJar for chain");
  }
  require(IV3OpenFeeAdapter(v3Adapter).TOKEN_JAR() == jar, "v3OpenFeeAdapter.TOKEN_JAR");
}

/// @dev Returns the L1CrossDomainMessenger on Ethereum that reaches `chainId`.
function l1Messenger(Uniswap storage uniswap, uint256 chainId) view returns (address) {
  if (chainId == ChainId.Celo) return uniswap.ethereum.bridge.celo;
  if (chainId == ChainId.Soneium) return uniswap.ethereum.bridge.soneium;
  if (chainId == ChainId.WorldChain) return uniswap.ethereum.bridge.worldChain;
  if (chainId == ChainId.XLayer) return uniswap.ethereum.bridge.xLayer;
  if (chainId == ChainId.Zora) return uniswap.ethereum.bridge.zora;
  revert("no L1CrossDomainMessenger for chain");
}

/// @dev The five chains, in the order of the proposal's actions.
function chains() pure returns (uint256[5] memory) {
  return [ChainId.Celo, ChainId.Soneium, ChainId.XLayer, ChainId.WorldChain, ChainId.Zora];
}
