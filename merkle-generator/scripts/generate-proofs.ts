#!/usr/bin/env tsx
/**
 * Generate Proofs Script - Pre-generates all merkle proofs for batch submission
 *
 * This script:
 * 1. Loads the merkle tree from JSON
 * 2. Chunks all pairs into batches
 * 3. Generates multi-proofs for each batch
 * 4. Saves proofs to numbered files for submission
 *
 * Usage:
 *   pnpm run generate-proofs [options]
 *
 * Options:
 *   --batch-size <number>  Number of pairs per batch (default: 50)
 *   --output-dir <path>    Directory to save proof files (default: ./data/proofs)
 *   --max-batches <number> Maximum number of batches to generate (for testing)
 */

import { readFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { StandardMerkleTree } from '@openzeppelin/merkle-tree';
import { type Address, type Hex } from 'viem';
import { parseArgs } from 'node:util';
import { join } from 'node:path';

// Parse command-line arguments
const { values: options } = parseArgs({
  options: {
    'batch-size': { type: 'string' },
    'max-batches': { type: 'string' },
  },
  strict: true,
  allowPositionals: false,
});

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
const TREE_FILE = './data/merkle-tree.json';
const OUTPUT_DIR = './data/proofs';
const BATCH_SIZE = parseInt(options['batch-size'] || '250', 10);
const MAX_BATCHES = options['max-batches'] ? parseInt(options['max-batches'], 10) : undefined;

// Validation
if (!existsSync(TREE_FILE)) {
  console.error(`Error: Tree file not found at ${TREE_FILE}`);
  process.exit(1);
}

if (BATCH_SIZE <= 0 || BATCH_SIZE > 1000) {
  console.error('Error: Batch size must be between 1 and 1000');
  process.exit(1);
}

async function main() {
  console.log('=== Merkle Proof Generation Script ===\n');
  console.log(`Configuration:`);
  console.log(`  Tree file: ${TREE_FILE}`);
  console.log(`  Batch size: ${BATCH_SIZE}`);
  console.log(`  Output directory: ${OUTPUT_DIR}`);
  console.log(`  Max batches: ${MAX_BATCHES || 'unlimited'}\n`);

  // Create output directory if it doesn't exist
  if (!existsSync(OUTPUT_DIR)) {
    console.log(`Creating output directory: ${OUTPUT_DIR}`);
    mkdirSync(OUTPUT_DIR, { recursive: true });
  }

  // Load merkle tree
  console.log('Loading merkle tree...');
  const treeData = JSON.parse(readFileSync(TREE_FILE, 'utf-8'));
  const tree = StandardMerkleTree.load<[Address, Address]>(treeData);
  console.log(`  Root: ${tree.root}`);

  // Get all pairs from the tree
  const allPairs: Array<[number, [Address, Address]]> = [];
  for (const entry of tree.entries()) {
    allPairs.push(entry);
  }
  console.log(`  Total pairs: ${allPairs.length}\n`);

  // Calculate total batches
  const totalPairs = MAX_BATCHES ? Math.min(allPairs.length, MAX_BATCHES * BATCH_SIZE) : allPairs.length;
  const totalBatches = Math.ceil(totalPairs / BATCH_SIZE);

  console.log(`Generating proofs for ${totalPairs} pairs in ${totalBatches} batches...\n`);

  const timestamp = new Date().toISOString();

  // Process pairs in batches
  for (let i = 0; i < totalPairs; i += BATCH_SIZE) {
    const batchNum = Math.floor(i / BATCH_SIZE) + 1;
    const batchEnd = Math.min(i + BATCH_SIZE, totalPairs);
    const batchPairs = allPairs.slice(i, batchEnd);

    process.stdout.write(`Generating batch ${batchNum}/${totalBatches}... `);

    try {
      // Generate multi-proof for this batch
      const indices = batchPairs.map(([index]) => index);
      const multiProof = tree.getMultiProof(indices);

      // Verify proof locally
      const isValid = tree.verifyMultiProof(multiProof);
      if (!isValid) {
        throw new Error(`❌ Proof verification failed for batch ${batchNum}`);
      }

      // Prepare pairs for the proof batch
      const pairs: Pair[] = multiProof.leaves.map(leaf => ({
        token0: leaf[0] as Address,
        token1: leaf[1] as Address,
      }));

      // Create proof batch object
      const proofBatch: ProofBatch = {
        batchNumber: batchNum,
        startIndex: i,
        endIndex: batchEnd - 1,
        pairCount: pairs.length,
        pairs,
        multiProof: {
          leaves: multiProof.leaves as [Address, Address][],
          proof: multiProof.proof as Hex[],
          proofFlags: multiProof.proofFlags,
        },
        treeRoot: tree.root,
        timestamp,
        metadata: {
          treeFile: TREE_FILE,
          batchSize: BATCH_SIZE,
          totalPairs: allPairs.length,
          totalBatches,
        },
      };

      // Save proof to file
      const filename = `proof-batch-${String(batchNum).padStart(4, '0')}.json`;
      const filepath = join(OUTPUT_DIR, filename);
      writeFileSync(filepath, JSON.stringify(proofBatch, null, 2));

      console.log(`✓ (${pairs.length} pairs)`);
    } catch (error) {
      throw new Error(`❌ Error: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  // Summary
  console.log('\n=== Summary ===');
  console.log(`Output directory: ${OUTPUT_DIR}`);

  console.log('\n✅ All proofs generated successfully!');
  console.log('\nNext steps:');
  console.log('1. Review the generated proofs in the output directory');
  console.log('2. Run `pnpm run submit-proofs` to submit them on-chain');
}

// Run the script
main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
