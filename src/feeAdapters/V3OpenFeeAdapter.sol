// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Owned} from "solmate/src/auth/Owned.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {
  IUniswapV3PoolOwnerActions
} from "v3-core/contracts/interfaces/pool/IUniswapV3PoolOwnerActions.sol";
import {IV3OpenFeeAdapter} from "../interfaces/IV3OpenFeeAdapter.sol";
import {ArrayLib} from "../libraries/ArrayLib.sol";

/// @title V3OpenFeeAdapter
/// @notice A permissionless contract that allows anyone to trigger protocol fee updates for pools.
/// @dev This is a simplified version of V3FeeAdapter that removes Merkle proof authorization.
/// Fee updates are permissionless - anyone can call triggerFeeUpdate to apply the default fees
/// set by the feeSetter. This contract will be the set owner on the Uniswap V3 Factory.
/// @custom:security-contact security@uniswap.org
contract V3OpenFeeAdapter is IV3OpenFeeAdapter, Owned {
  using ArrayLib for uint24[];

  /// @inheritdoc IV3OpenFeeAdapter
  IUniswapV3Factory public immutable FACTORY;
  /// @inheritdoc IV3OpenFeeAdapter
  address public immutable TOKEN_JAR;

  /// @inheritdoc IV3OpenFeeAdapter
  address public feeSetter;

  /// @inheritdoc IV3OpenFeeAdapter
  mapping(uint24 feeTier => uint8 defaultFeeValue) public defaultFees;

  /// @return The fee tiers that are enabled on the factory. Iterable so that the protocol fee for
  /// pools of the same pair can be activated with the same call.
  /// @dev Returns four enabled fee tiers: 100, 500, 3000, 10000. May return more if more are
  /// enabled.
  uint24[] public feeTiers;

  /// @notice Ensures only the fee setter can call the setDefaultFeeByFeeTier function
  modifier onlyFeeSetter() {
    require(msg.sender == feeSetter, Unauthorized());
    _;
  }

  /// @dev At construction, the fee setter defaults to 0 and its on the owner to set.
  constructor(address _factory, address _tokenJar) Owned(msg.sender) {
    FACTORY = IUniswapV3Factory(_factory);
    TOKEN_JAR = _tokenJar;
  }

  /// @inheritdoc IV3OpenFeeAdapter
  function storeFeeTier(uint24 feeTier) public {
    require(_feeTierExists(feeTier), InvalidFeeTier());
    require(!feeTiers.includes(feeTier), TierAlreadyStored());
    feeTiers.push(feeTier);
  }

  /// @inheritdoc IV3OpenFeeAdapter
  function enableFeeAmount(uint24 fee, int24 tickSpacing) external onlyOwner {
    FACTORY.enableFeeAmount(fee, tickSpacing);

    storeFeeTier(fee);
  }

  /// @notice Transfer ownership of the Uniswap V3 Factory to a new address
  /// @dev Only callable by the owner of this contract. This is a critical operation
  ///      as it transfers control of the V3 Factory
  /// @param newOwner The address that will become the new owner of the V3 Factory
  function setFactoryOwner(address newOwner) external onlyOwner {
    FACTORY.setOwner(newOwner);
  }

  /// @inheritdoc IV3OpenFeeAdapter
  function collect(CollectParams[] calldata collectParams)
    external
    returns (Collected[] memory amountsCollected)
  {
    amountsCollected = new Collected[](collectParams.length);
    for (uint256 i = 0; i < collectParams.length; i++) {
      CollectParams calldata params = collectParams[i];
      (uint128 amount0Collected, uint128 amount1Collected) = IUniswapV3PoolOwnerActions(params.pool)
        .collectProtocol(TOKEN_JAR, params.amount0Requested, params.amount1Requested);

      amountsCollected[i] =
        Collected({amount0Collected: amount0Collected, amount1Collected: amount1Collected});
    }
  }

  /// @inheritdoc IV3OpenFeeAdapter
  function setDefaultFeeByFeeTier(uint24 feeTier, uint8 defaultFeeValue) external onlyFeeSetter {
    require(_feeTierExists(feeTier), InvalidFeeTier());
    // Extract the two 4-bit values
    uint8 feeProtocol0 = defaultFeeValue % 16;
    uint8 feeProtocol1 = defaultFeeValue >> 4;
    // Validate both values match pool requirements: must be 0 or in range [4, 10]
    require(
      (feeProtocol0 == 0 || (feeProtocol0 >= 4 && feeProtocol0 <= 10))
        && (feeProtocol1 == 0 || (feeProtocol1 >= 4 && feeProtocol1 <= 10)),
      InvalidFeeValue()
    );
    defaultFees[feeTier] = defaultFeeValue;
  }

  /// @inheritdoc IV3OpenFeeAdapter
  function setFeeSetter(address newFeeSetter) external onlyOwner {
    feeSetter = newFeeSetter;
  }

  /// @inheritdoc IV3OpenFeeAdapter
  function triggerFeeUpdate(address pool) external {
    // Check pool exists before calling fee()
    uint256 size;
    assembly {
      size := extcodesize(pool)
    }
    if (size == 0) return;
    _setProtocolFee(pool, IUniswapV3Pool(pool).fee());
  }

  /// @inheritdoc IV3OpenFeeAdapter
  function triggerFeeUpdate(address token0, address token1) external {
    _setProtocolFeesForPair(token0, token1);
  }

  /// @inheritdoc IV3OpenFeeAdapter
  function batchTriggerFeeUpdate(Pair[] calldata pairs) external {
    uint256 length = pairs.length;
    for (uint256 i; i < length;) {
      _setProtocolFeesForPair(pairs[i].token0, pairs[i].token1);
      unchecked {
        ++i;
      }
    }
  }

  /// @inheritdoc IV3OpenFeeAdapter
  function batchTriggerFeeUpdateByPool(address[] calldata pools) external {
    uint256 length = pools.length;
    uint256 size;
    for (uint256 i; i < length;) {
      address pool = pools[i];
      assembly {
        size := extcodesize(pool)
      }
      if (size > 0) _setProtocolFee(pool, IUniswapV3Pool(pool).fee());
      unchecked {
        ++i;
      }
    }
  }

  /// @notice Sets protocol fees for all existing pools of a token pair across all fee tiers
  /// @dev Iterates through all stored fee tiers and sets the protocol fee for each pool that exists
  /// @param token0 The first token of the pair
  /// @param token1 The second token of the pair
  function _setProtocolFeesForPair(address token0, address token1) internal {
    uint24 feeTier;
    address pool;
    uint256 length = feeTiers.length;
    for (uint256 i; i < length;) {
      feeTier = feeTiers[i];
      pool = FACTORY.getPool(token0, token1, feeTier);
      if (pool != address(0)) _setProtocolFee(pool, feeTier);
      unchecked {
        ++i;
      }
    }
  }

  /// @notice Sets the protocol fee for a specific pool based on its fee tier
  /// @dev Only sets the fee for initialized pools (sqrtPriceX96 != 0).
  ///      Includes idempotency check to skip if fees already match.
  ///      The feeValue encodes both fee0 (lower 4 bits) and fee1 (upper 4 bits)
  /// @param pool The address of the Uniswap V3 pool
  /// @param feeTier The fee tier of the pool, used to look up the default fee value
  function _setProtocolFee(address pool, uint24 feeTier) internal {
    // Gas optimization: Check pool exists before expensive slot0 read
    uint256 size;
    assembly {
      size := extcodesize(pool)
    }
    if (size == 0) return;

    // Check if pool is initialized and get current fee protocol
    (uint160 sqrtPriceX96,,,, uint16 currentFeeProtocol,,) = IUniswapV3Pool(pool).slot0();
    if (sqrtPriceX96 == 0) return; // Pool exists but not initialized, skip

    uint8 feeValue = defaultFees[feeTier];

    // Idempotency check: Skip if already set (prevents griefing)
    if (uint8(currentFeeProtocol) == feeValue) return;

    IUniswapV3PoolOwnerActions(pool).setFeeProtocol(feeValue % 16, feeValue >> 4);

    emit FeeUpdateTriggered(msg.sender, pool, feeValue);
  }

  /// @notice Checks if a fee tier exists in the Uniswap V3 Factory
  /// @dev Verifies existence by checking if the tick spacing for the fee tier is non-zero
  /// @param feeTier The fee tier to check
  /// @return True if the fee tier exists, false otherwise
  function _feeTierExists(uint24 feeTier) internal view returns (bool) {
    if (FACTORY.feeAmountTickSpacing(feeTier) == 0) return false;
    return true;
  }
}
