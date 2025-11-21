#!/usr/bin/env tsx
/**
 * Submit Proofs Script - Submits pre-generated merkle proofs to the V3FeeAdapter
 *
 * This script:
 * 1. Loads pre-generated proof files from the proofs directory
 * 2. Connects to the blockchain with a wallet
 * 3. Submits each proof batch in order
 * 4. Tracks progress and allows resuming from failures
 *
 * Usage:
 *   pnpm run submit-proofs [options]
 *
 * Options:
 *   --rpc-url <url>        RPC URL (required via env or flag)
 *   --dry-run              Simulate transactions without sending
 *   --start-batch <number> Start from specific batch number (for resuming)
 *   --chain <name>         Chain name: mainnet, sepolia, optimism, etc (default: mainnet)
 */

import { readFileSync, existsSync, writeFileSync, readdirSync } from 'node:fs';
import {
  createWalletClient,
  createPublicClient,
  http,
  type Address,
  type Hex,
  type Chain,
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { mainnet, sepolia, optimism, arbitrum, base } from 'viem/chains';
import { config } from 'dotenv';
import { parseArgs } from 'node:util';
import { join } from 'node:path';
import V3FeeAdapterArtifact from '../../out/V3FeeAdapter.sol/V3FeeAdapter.json' assert { type: 'json' };

// Load environment variables
config();

// Parse command-line arguments
const { values: options } = parseArgs({
  options: {
    'rpc-url': { type: 'string' },
    'dry-run': { type: 'boolean' },
    'start-batch': { type: 'string' },
  },
  strict: true,
  allowPositionals: false,
});

// Use the ABI from the compiled contract artifact
const V3_FEE_ADAPTER_ABI = V3FeeAdapterArtifact.abi;

// Type definitions
interface Pair {
  token0: Address;
  token1: Address;
}

interface MultiProof {
  leaves: [Address, Address][];
  proof: Hex[];
  proofFlags: boolean[];
}

interface ProofBatch {
  batchNumber: number;
  startIndex: number;
  endIndex: number;
  pairCount: number;
  pairs: Pair[];
  multiProof: MultiProof;
  treeRoot: string;
  timestamp: string;
  metadata: {
    treeFile: string;
    batchSize: number;
    totalPairs: number;
    totalBatches: number;
  };
}

// Configuration
const PROOFS_DIR = './data/proofs';
// TODO: add fee adapter address
const FEE_ADAPTER = '0xf72EF58d39236f587c1CbC0c8Da606E8f64d9c3a' as Address;
const RPC_URL = options['rpc-url'] || process.env.RPC_URL;
const PRIVATE_KEY = process.env.PRIVATE_KEY as Hex;
const DRY_RUN = options['dry-run'] ?? false;
const START_BATCH = parseInt(options['start-batch'] || '1', 10);
const chain = mainnet;

// Validation
if (!FEE_ADAPTER || FEE_ADAPTER === '0x0000000000000000000000000000000000000000') {
  throw new Error('FEE_ADAPTER_ADDRESS must be set in the script');
}

if (!RPC_URL) {
  throw new Error('RPC_URL must be provided via --rpc-url flag or environment variable');
}

if (!PRIVATE_KEY && !DRY_RUN) {
  throw new Error('PRIVATE_KEY must be provided via environment variable (unless using --dry-run)');
}

if (!existsSync(PROOFS_DIR)) {
  throw new Error(`Proofs directory not found at ${PROOFS_DIR}. Run generate-proofs first.`);
}

function loadProofFiles(): string[] {
  // Read all proof batch files from the directory
  const files = readdirSync(PROOFS_DIR)
    .filter(f => f.startsWith('proof-batch-') && f.endsWith('.json'))
    .sort(); // Sort to ensure correct order (0001, 0002, etc.)

  if (files.length === 0) {
    throw new Error(`No proof files found in ${PROOFS_DIR}. Run generate-proofs first.`);
  }

  return files;
}

async function loadProofBatch(filename: string): Promise<ProofBatch> {
  const filepath = join(PROOFS_DIR, filename);
  if (!existsSync(filepath)) {
    throw new Error(`Proof file not found: ${filepath}`);
  }
  return JSON.parse(readFileSync(filepath, 'utf-8'));
}

async function main() {
  console.log('=== Merkle Proof Submission Script ===\n');
  console.log(`Configuration:`);
  console.log(`  Proofs directory: ${PROOFS_DIR}`);
  console.log(`  Fee adapter: ${FEE_ADAPTER}`);
  console.log(`  Chain: ${chain.name} (${chain.id})`);
  console.log(`  RPC URL: ${RPC_URL}`);
  console.log(`  Dry run: ${DRY_RUN}`);
  console.log(`  Start batch: ${START_BATCH}\n`);

  // Load proof files
  console.log('Loading proof files...');
  const proofFiles = loadProofFiles();
  console.log(`  Found ${proofFiles.length} proof files\n`);

  // Setup clients
  const publicClient = createPublicClient({
    chain,
    transport: http(RPC_URL),
  });

  let walletClient;
  let account;

  if (!DRY_RUN) {
    account = privateKeyToAccount(PRIVATE_KEY);
    walletClient = createWalletClient({
      account,
      chain,
      transport: http(RPC_URL),
    });
    console.log(`Wallet address: ${account.address}\n`);
  }

  // Load first proof to get tree root for verification
  const firstProof = await loadProofBatch(proofFiles[0]);
  const treeRoot = firstProof.treeRoot;

  // Check on-chain merkle root (skip in dry run if it fails)
  console.log('Checking on-chain merkle root...');
  const onChainRoot = await publicClient.readContract({
    address: FEE_ADAPTER,
    abi: V3_FEE_ADAPTER_ABI,
    functionName: 'merkleRoot',
  }) as string;

  console.log(`  On-chain root: ${onChainRoot}`);
  console.log(`  Proof root:    ${treeRoot}`);

  if (onChainRoot !== treeRoot) {
    throw new Error('On-chain merkle root does not match proof root! V3FeeAdapter needs merkle root update.');
  }

  console.log('✓ Merkle roots match!\n');

  // Determine which batches to submit
  const batchesToSubmit: ProofBatch[] = [];

  for (const filename of proofFiles) {
    const proofBatch = await loadProofBatch(filename);
    const batchNumber = proofBatch.batchNumber;

    // Apply start batch filter
    if (batchNumber < START_BATCH) {
      continue;
    }

    batchesToSubmit.push(proofBatch);
  }

  if (batchesToSubmit.length === 0) {
    console.log('No batches to submit. All batches may have been previously submitted.');
    return;
  }

  const totalBatches = proofFiles.length;
  console.log(`Submitting ${batchesToSubmit.length} of ${totalBatches} total batches...\n`);

  let successCount = 0;
  let totalGasUsed = 0n;

  // Submit each batch
  for (const proofBatch of batchesToSubmit) {
    const batchNumber = proofBatch.batchNumber;

    console.log(`\n--- Batch ${batchNumber}/${totalBatches} ---`);
    console.log(`  Pairs ${proofBatch.startIndex + 1} to ${proofBatch.endIndex + 1} (${proofBatch.pairCount} pairs)`);

    // Prepare submission status
    if (DRY_RUN) {
      console.log('  🔍 Dry run - estimating gas...');

      const gasEstimate = await publicClient.estimateContractGas({
        address: FEE_ADAPTER,
        abi: V3_FEE_ADAPTER_ABI,
        functionName: 'batchTriggerFeeUpdate',
        args: [proofBatch.pairs, proofBatch.multiProof.proof, proofBatch.multiProof.proofFlags],
        account: account || '0x0000000000000000000000000000000000000000',
      });

      console.log(`  ⛽ Estimated gas: ${gasEstimate.toLocaleString()}`);
      successCount++;

    } else {
      console.log('  📤 Sending transaction...');

      const hash = await walletClient!.writeContract({
        address: FEE_ADAPTER,
        abi: V3_FEE_ADAPTER_ABI,
        functionName: 'batchTriggerFeeUpdate',
        args: [proofBatch.pairs, proofBatch.multiProof.proof, proofBatch.multiProof.proofFlags],
      });

      console.log(`  📝 Transaction hash: ${hash}`);
      console.log('  ⏳ Waiting for confirmation...');

      const receipt = await publicClient.waitForTransactionReceipt({ hash });

      if (receipt.status !== 'success') {
        throw new Error(`Transaction reverted for batch ${batchNumber}`);
      }

      console.log(`  ✅ Transaction confirmed in block ${receipt.blockNumber}`);
      console.log(`  ⛽ Gas used: ${receipt.gasUsed.toLocaleString()}`);
    }

    // Display sample pairs
    console.log('  Sample pairs from this batch:');
    const sampleSize = Math.min(3, proofBatch.pairs.length);
    for (let i = 0; i < sampleSize; i++) {
      const pair = proofBatch.pairs[i];
      console.log(`    ${pair.token0} <-> ${pair.token1}`);
    }
    if (proofBatch.pairs.length > sampleSize) {
      console.log(`    ... and ${proofBatch.pairs.length - sampleSize} more`);
    }
  }

  // Final summary
  console.log('\n=== Summary ===');
  console.log(`Batches processed: ${successCount}`);

  if (!DRY_RUN && totalGasUsed > 0n) {
    console.log(`Total gas used: ${totalGasUsed.toLocaleString()}`);
  }
}

// Run the script
main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
