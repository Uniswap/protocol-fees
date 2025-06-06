// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {V3FeeManager} from "src/V3FeeManager.sol";
import {IUniswapV3FactoryOwnerActions} from "src/interfaces/IUniswapV3FactoryOwnerActions.sol";

contract V3FeeManagerHarness is V3FeeManager {
  constructor(
    address _admin,
    IUniswapV3FactoryOwnerActions _factory,
    IERC20 _payoutToken,
    uint256 _payoutAmount,
    uint8 _globalProtocolFee,
    address _rewardReceiver
  )
    V3FeeManager(_admin, _factory, _payoutToken, _payoutAmount, _globalProtocolFee, _rewardReceiver)
  {}

  function exposed_setAdmin(address _newAdmin) external {
    _setAdmin(_newAdmin);
  }

  function exposed_setPayoutAmount(uint256 _payoutAmount) external {
    _setPayoutAmount(_payoutAmount);
  }

  function exposed_setGlobalProtocolFee(uint8 _globalProtocolFee) external {
    _setGlobalProtocolFee(_globalProtocolFee);
  }

  function exposed_claimFees(V3FeeManager.ClaimInputData calldata _input)
    external
    returns (V3FeeManager.ClaimOutputData memory)
  {
    return _claimFees(_input);
  }

  function exposed_revertIfNotAdmin() external view {
    _revertIfNotAdmin();
  }
}
