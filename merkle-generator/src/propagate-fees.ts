import type { Contract, JsonRpcProvider } from 'ethers';

/**
 * Discover all V3 pool addresses by scanning PoolCreated events from the factory.
 * Chunks the block range to respect RPC provider limits.
 */
export async function discoverPools(
  factoryContract: Contract,
  provider: JsonRpcProvider,
  fromBlock: number,
  chunkSize: number,
): Promise<string[]> {
  const latestBlock = await provider.getBlockNumber();
  const poolSet = new Set<string>();

  for (let start = fromBlock; start <= latestBlock; start += chunkSize) {
    const end = Math.min(start + chunkSize - 1, latestBlock);
    console.log(`  Scanning blocks ${start} - ${end}...`);

    const events = await factoryContract.queryFilter(
      factoryContract.filters.PoolCreated(),
      start,
      end,
    );

    for (const event of events) {
      const poolAddress = (event as any).args[4] as string;
      poolSet.add(poolAddress);
    }
  }

  return Array.from(poolSet);
}

export interface PoolFeeStatus {
  initialized: number;
  uninitialized: number;
  correct: number;
  needsUpdate: string[];
}

/**
 * Check each pool's current fee against the adapter's expected fee.
 * Returns which pools need updates and summary counts.
 */
export async function checkFees(
  pools: string[],
  adapterContract: Contract,
  createPoolContract: (address: string) => Contract,
): Promise<PoolFeeStatus> {
  let initialized = 0;
  let uninitialized = 0;
  let correct = 0;
  const needsUpdate: string[] = [];

  for (const pool of pools) {
    const poolContract = createPoolContract(pool);
    const slot0 = await poolContract.slot0();
    const sqrtPriceX96 = slot0.sqrtPriceX96 ?? slot0[0];
    const actualFee = Number(slot0.feeProtocol ?? slot0[5]);

    if (sqrtPriceX96 === 0n) {
      uninitialized++;
      continue;
    }

    initialized++;

    const expectedFee = Number(await adapterContract.getFee(pool));

    if (actualFee === expectedFee) {
      correct++;
    }
    else {
      needsUpdate.push(pool);
    }
  }

  return { initialized, uninitialized, correct, needsUpdate };
}

export interface BatchResult {
  txHash: string;
  gasUsed: bigint;
  poolCount: number;
}

/**
 * Send batchTriggerFeeUpdateByPool transactions in chunks.
 * Waits for each tx receipt before proceeding.
 */
export async function executeBatchUpdate(
  pools: string[],
  adapterContract: Contract,
  batchSize: number,
): Promise<BatchResult[]> {
  if (pools.length === 0) return [];

  const results: BatchResult[] = [];

  for (let i = 0; i < pools.length; i += batchSize) {
    const batch = pools.slice(i, i + batchSize);
    const batchNum = Math.floor(i / batchSize) + 1;
    const totalBatches = Math.ceil(pools.length / batchSize);

    console.log(`  Batch ${batchNum}/${totalBatches}: ${batch.length} pools...`);

    const tx = await adapterContract.batchTriggerFeeUpdateByPool(batch);
    const receipt = await tx.wait();

    results.push({
      txHash: receipt.hash,
      gasUsed: receipt.gasUsed,
      poolCount: batch.length,
    });

    console.log(`    tx: ${receipt.hash}, gas: ${receipt.gasUsed}`);
  }

  return results;
}
