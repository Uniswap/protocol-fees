import { Contract, JsonRpcProvider, Wallet } from 'ethers';

import { V3_FACTORY_ABI, V3_OPEN_FEE_ADAPTER_ABI, V3_POOL_ABI } from './abi.js';

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

export interface PropagateFeeOptions {
  rpcUrl: string;
  adapterAddress: string;
  factoryAddress: string;
  privateKey: string;
  batchSize: number;
  fromBlock: number;
  chunkSize: number;
}

/**
 * Main orchestrator: discover pools, check fees, batch-update incorrect ones.
 */
export async function propagateFees(options: PropagateFeeOptions): Promise<void> {
  const provider = new JsonRpcProvider(options.rpcUrl);
  const wallet = new Wallet(options.privateKey, provider);
  const network = await provider.getNetwork();

  console.log(`Chain ID: ${network.chainId}`);
  console.log(`Factory: ${options.factoryAddress}`);
  console.log(`Adapter: ${options.adapterAddress}`);
  console.log(`Sender: ${wallet.address}`);
  console.log('');

  // 1. Discover pools
  console.log('Step 1: Discovering pools...');
  const factoryContract = new Contract(options.factoryAddress, V3_FACTORY_ABI, provider);
  const pools = await discoverPools(factoryContract, provider, options.fromBlock, options.chunkSize);
  console.log(`  Found ${pools.length} pools\n`);

  if (pools.length === 0) {
    console.log('No pools found. Done.');
    return;
  }

  // 2. Check fees
  console.log('Step 2: Checking pool fees...');
  const adapterContract = new Contract(options.adapterAddress, V3_OPEN_FEE_ADAPTER_ABI, wallet);
  const createPoolContract = (address: string) => new Contract(address, V3_POOL_ABI, provider);

  const status = await checkFees(pools, adapterContract, createPoolContract);
  console.log(`  Initialized: ${status.initialized}`);
  console.log(`  Uninitialized: ${status.uninitialized}`);
  console.log(`  Already correct: ${status.correct}`);
  console.log(`  Needs update: ${status.needsUpdate.length}\n`);

  if (status.needsUpdate.length === 0) {
    console.log('All pools have correct fees. Done.');
    return;
  }

  // 3. Execute batch updates
  console.log('Step 3: Sending transactions...');
  const results = await executeBatchUpdate(status.needsUpdate, adapterContract, options.batchSize);

  // 4. Summary
  console.log('\n=== Summary ===');
  console.log(`Pools discovered: ${pools.length}`);
  console.log(`Pools updated: ${status.needsUpdate.length}`);
  console.log(`Transactions sent: ${results.length}`);
  const totalGas = results.reduce((sum, r) => sum + r.gasUsed, 0n);
  console.log(`Total gas used: ${totalGas}`);
  for (const [i, result] of results.entries()) {
    console.log(`  Batch ${i + 1}: ${result.poolCount} pools, tx ${result.txHash}, gas ${result.gasUsed}`);
  }
  console.log('\nDone. All pools now have correct protocol fees.');
}
