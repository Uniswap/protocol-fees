// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IInbox} from "govkit/interfaces/bridges/IInbox.sol";
import {ICrossChainAccount} from "govkit/interfaces/bridges/ICrossChainAccount.sol";
import {Predeploys} from "@eth-optimism-bedrock/src/libraries/Predeploys.sol";
import {
  ICrossDomainMessenger
} from "@eth-optimism-bedrock/interfaces/universal/ICrossDomainMessenger.sol";
import {IArbSys} from "briefcase/protocols/uniswapx/interfaces/IArbSys.sol";

import {vm} from "govkit/forge/Constants.sol";
import {WormholeChainId} from "govkit/constants/WormholeChainId.sol";
import {WormholeEncoder} from "govkit/bridges/WormholeEncoder.sol";

import {IUniswapWormholeMessageReceiver} from "../proposal-7/Interfaces.sol";

/// @dev The part of an Arbitrum bridge on Ethereum the preflights read: the rollup it serves.
interface IArbitrumBridge {
  function rollup() external view returns (address);
}

/// @dev The part of an Arbitrum rollup on Ethereum the preflights read: the chain the rollup runs.
interface IArbitrumRollup {
  function chainId() external view returns (uint256);
}

/// @dev The getters of Polygon's `EthereumProxy` that the preflights read.
interface IEthereumProxy {
  function fxChild() external view returns (address);
  function l1Owner() external view returns (address);
}

/// @dev The getter of Polygon's FxChild that the preflights read.
interface IFxChild {
  function fxRoot() external view returns (address);
}

/// @dev The ArbSys precompile on Arbitrum and on Orbit chains such as Robinhood Chain.
IArbSys constant ARB_SYS = IArbSys(address(0x64));

/// @notice Asserts on Ethereum that `l1Messenger` is an unpaused OP Stack L1CrossDomainMessenger.
function checkOPStackMessengerEthereum(address l1Messenger, string memory label) view {
  ICrossDomainMessenger messenger = ICrossDomainMessenger(l1Messenger);
  require(
    address(messenger.OTHER_MESSENGER()) == Predeploys.L2_CROSS_DOMAIN_MESSENGER,
    string.concat(label, ".l1CrossDomainMessenger.other")
  );
  require(!messenger.paused(), string.concat(label, ".l1CrossDomainMessenger.paused"));
}

/// @notice Asserts on an OP Stack chain that `crossChainAccount` runs only messages that the
///         Timelock sends through `l1Messenger`.
function checkCrossChainAccount(address crossChainAccount, address l1Messenger, address timelock)
  view {
  require(
    address(ICrossDomainMessenger(Predeploys.L2_CROSS_DOMAIN_MESSENGER).OTHER_MESSENGER())
      == l1Messenger,
    "l2CrossDomainMessenger.other"
  );
  (address messenger, address l1Owner) = _crossChainAccountFields(crossChainAccount);
  require(messenger == Predeploys.L2_CROSS_DOMAIN_MESSENGER, "crossChainAccount.messenger");
  require(l1Owner == timelock, "crossChainAccount.l1Owner");
}

/// @notice Returns the `messenger` and `l1Owner` of `crossChainAccount`.
function _crossChainAccountFields(address crossChainAccount)
  view
  returns (address messenger, address l1Owner)
{
  try ICrossChainAccount(crossChainAccount).messenger() returns (address value) {
    return (value, ICrossChainAccount(crossChainAccount).l1Owner());
  } catch {
    // Assume the account is the older CrossChainAccount, as on World Chain and Zora. It has no
    // getters and stores `messenger` at slot 0 and `l1Owner` at slot 1.
    messenger = address(uint160(uint256(vm.load(crossChainAccount, bytes32(uint256(0))))));
    l1Owner = address(uint160(uint256(vm.load(crossChainAccount, bytes32(uint256(1))))));
  }
}

/// @notice Asserts on Ethereum that `inbox` is unpaused and delivers to the chain `chainId`.
function checkInboxEthereum(address inbox, uint256 chainId, string memory label) view {
  require(
    IArbitrumRollup(IArbitrumBridge(IInbox(inbox).bridge()).rollup()).chainId() == chainId,
    string.concat(label, ".inbox.rollup.chainId")
  );
  require(!IInbox(inbox).paused(), string.concat(label, ".inbox.paused"));
}

/// @notice Asserts that `receiver`, a `UniswapWormholeMessageReceiver`, runs only messages that
///         `sender` publishes on Ethereum, and, if the receiver checks the destination chain, only
///         messages for the Wormhole chain `wormholeChainId`.
function checkWormholeReceiver(address receiver, address sender, uint16 wormholeChainId) view {
  IUniswapWormholeMessageReceiver wormholeReceiver = IUniswapWormholeMessageReceiver(receiver);
  require(
    wormholeReceiver.messageSender() == WormholeEncoder.toWormholeFormat(sender),
    "receiver.messageSender"
  );
  require(
    wormholeReceiver.ETHEREUM_CHAIN_ID() == WormholeChainId.Ethereum, "receiver.ethereumChainId"
  );
  try wormholeReceiver.chainId() returns (uint16 chainId) {
    require(chainId == wormholeChainId, "receiver.chainId");
  } catch {
    // Assume the receiver is the older receiver, as on BNB Chain, which has no `chainId()` and
    // does not check the chain a message is addressed to.
  }
}

/// @notice Asserts on Polygon that `ethereumProxy` runs only messages that the Timelock sends
///         through `fxRoot`, delivered by `fxChild`.
function checkEthereumProxy(
  address ethereumProxy,
  address fxChild,
  address fxRoot,
  address timelock
) view {
  require(IEthereumProxy(ethereumProxy).fxChild() == fxChild, "ethereumProxy.fxChild");
  require(IEthereumProxy(ethereumProxy).l1Owner() == timelock, "ethereumProxy.l1Owner");
  require(IFxChild(fxChild).fxRoot() == fxRoot, "fxChild.fxRoot");
}
