// Minimal ABIs for on-chain interactions

export const V3_FACTORY_ABI = [
  'event PoolCreated(address indexed token0, address indexed token1, uint24 indexed fee, int24 tickSpacing, address pool)',
] as const;

export const V3_POOL_ABI = [
  'function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked)',
] as const;

export const V3_OPEN_FEE_ADAPTER_ABI = [
  'function getFee(address pool) external view returns (uint8 fee)',
  'function batchTriggerFeeUpdateByPool(address[] calldata pools) external',
] as const;
