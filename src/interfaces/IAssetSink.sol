// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Currency} from "v4-core/types/Currency.sol";

interface IAssetSink {
  function releaser() external view returns (address);
  function setReleaser(address _releaser) external;
  function release(Currency[] calldata assets, address recipient) external;
}
