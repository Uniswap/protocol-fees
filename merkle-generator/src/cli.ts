#!/usr/bin/env node

import { readFileSync, writeFileSync } from 'node:fs';
import { StandardMerkleTree } from '@openzeppelin/merkle-tree';
import { Command } from 'commander';
import { formatAddress, parseCSV, sortTokenPair } from './utils.js';

const program = new Command();

program
  .name('merkle-generator')
  .description('CLI tool for generating Merkle trees and proofs for Uniswap V3 fee adapter')
  .version('0.0.0');

// Generate command
program
  .command('generate')
  .description('Generate a Merkle tree from a CSV file containing token pairs')
  .argument('[input-file]', 'Path to CSV file containing token pairs (one pair per row)', './data/token-pairs.csv')
  .option('-o, --output <file>', 'Output file for the Merkle tree', './data/merkle-tree.json')
  .action(async (inputFile, options) => {
    try {
      console.log('Generating Merkle tree from:', inputFile);

      // Read input file
      const content = readFileSync(inputFile, 'utf-8');

      // Parse CSV
      const pairs = parseCSV(content);
      console.log(`Processing ${pairs.length} token pairs`);

      // Create StandardMerkleTree - it handles double-hashing automatically!
      const tree = StandardMerkleTree.of(pairs, ['address', 'address']);

      // Save tree
      const treeData = tree.dump();
      writeFileSync(options.output, JSON.stringify(treeData, null, 2));

      console.log('\nMerkle tree generated successfully!');
      console.log('Root:', tree.root);
      console.log('Total pairs:', pairs.length);
      console.log('Tree saved to:', options.output);

      // Display first few leaves as examples
      console.log('\nExample pairs (first 3):');
      let count = 0;
      for (const [index, [token0, token1]] of tree.entries()) {
        if (count >= 3)
          break;
        console.log(`  [${index}] ${token0} <-> ${token1}`);
        console.log(`       Leaf hash: ${tree.leafHash([token0, token1])}`);
        count++;
      }
    }
    catch (error) {
      console.error('Error generating Merkle tree:', error instanceof Error ? error.message : String(error));
      process.exit(1);
    }
  });

// Prove command - generates multi-proof for one or more token pairs
program
  .command('prove')
  .description('Generate a Merkle multi-proof for token pairs')
  .argument('[tree-file]', 'Path to the Merkle tree JSON file', './data/merkle-tree.json')
  .argument('<pairs-input>', 'Token pair(s): either "token0,token1" or path to CSV file with multiple pairs')
  .option('-o, --output <file>', 'Output file for the multi-proof')
  .action(async (treeFile, pairsInput, options) => {
    try {
      console.log('Generating multi-proof from tree:', treeFile);

      // Load tree
      const treeData = JSON.parse(readFileSync(treeFile, 'utf-8'));
      const tree = StandardMerkleTree.load(treeData);

      // Parse pairs input - either a single pair or a CSV file
      let pairsToProve: [string, string][];

      if (pairsInput.includes('.csv') || pairsInput.includes('\n')) {
        // It's a file path or multiline input
        try {
          const pairsContent = readFileSync(pairsInput, 'utf-8');
          pairsToProve = parseCSV(pairsContent);
          console.log('Loading pairs from CSV file:', pairsInput);
        }
        catch {
          // Maybe it's inline CSV content
          pairsToProve = parseCSV(pairsInput);
          console.log('Parsing inline CSV pairs');
        }
      }
      else if (pairsInput.includes(',')) {
        // Single pair format: "token0,token1"
        const parts = pairsInput.split(',').map(s => s.trim());
        if (parts.length !== 2) {
          throw new Error('Invalid pair format. Use "token0,token1" or provide a CSV file');
        }
        const token0 = formatAddress(parts[0]);
        const token1 = formatAddress(parts[1]);
        pairsToProve = [sortTokenPair(token0, token1)];
        console.log('Processing single pair');
      }
      else {
        throw new Error('Invalid input. Provide either "token0,token1" or a path to CSV file');
      }

      console.log(`\nGenerating multi-proof for ${pairsToProve.length} pair(s)`);

      // Find indices for each pair
      const indices: number[] = [];
      const foundPairs: [string, string][] = [];

      for (const [token0, token1] of pairsToProve) {
        let found = false;
        for (const [index, [treeToken0, treeToken1]] of tree.entries()) {
          if (treeToken0 === token0 && treeToken1 === token1) {
            indices.push(index);
            foundPairs.push([token0, token1]);
            found = true;
            console.log(`  Found pair [${index}]: ${token0} <-> ${token1}`);
            break;
          }
        }
        if (!found) {
          throw new Error(`Token pair not found in tree: ${token0} <-> ${token1}`);
        }
      }

      // Generate multi-proof
      const multiProof = tree.getMultiProof(indices);

      console.log('\nMulti-proof generated successfully!');
      console.log('Number of pairs in proof:', multiProof.leaves.length);
      console.log('Proof elements:', multiProof.proof.length);
      console.log('Proof flags:', multiProof.proofFlags.length);

      // Verify the multi-proof
      const isValid = tree.verifyMultiProof(multiProof);
      console.log('Multi-proof valid:', isValid);

      // Also verify using static method
      const staticValid = StandardMerkleTree.verifyMultiProof(
        tree.root,
        ['address', 'address'],
        multiProof,
      );
      console.log('Static verification valid:', staticValid);

      // Prepare multi-proof data
      const multiProofData = {
        root: tree.root,
        pairs: multiProof.leaves.map(leaf => ({
          token0: leaf[0],
          token1: leaf[1],
        })),
        multiProof: {
          leaves: multiProof.leaves,
          proof: multiProof.proof,
          proofFlags: multiProof.proofFlags,
        },
        valid: isValid,
        usage: {
          description: 'Use this multi-proof for batch verification of multiple token pairs',
          note: 'The order of leaves may differ from input order - they are reordered by the tree',
        },
      };

      // Save multi-proof if output file specified
      if (options.output) {
        writeFileSync(options.output, JSON.stringify(multiProofData, null, 2));
        console.log('\nMulti-proof saved to:', options.output);
      }
      else {
        console.log('\nMulti-proof data (JSON):');
        console.log(JSON.stringify(multiProofData, null, 2));
      }
    }
    catch (error) {
      console.error('Error generating multi-proof:', error instanceof Error ? error.message : String(error));
      process.exit(1);
    }
  });

// Verify command - verifies a multi-proof (works for single or multiple pairs)
program
  .command('verify')
  .description('Verify a Merkle multi-proof')
  .argument('[tree-file]', 'Path to the Merkle tree JSON file', './data/merkle-tree.json')
  .argument('<proof-file>', 'Path to the multi-proof JSON file')
  .action(async (treeFile, proofFile) => {
    try {
      console.log('Verifying multi-proof...');

      // Load tree and multi-proof
      const treeData = JSON.parse(readFileSync(treeFile, 'utf-8'));
      const proofData = JSON.parse(readFileSync(proofFile, 'utf-8'));

      const tree = StandardMerkleTree.load(treeData);

      // Extract multi-proof data
      const { multiProof, pairs } = proofData;

      // Verify using instance method
      const isValid = tree.verifyMultiProof(multiProof);

      // Also verify using static method
      const staticValid = StandardMerkleTree.verifyMultiProof(
        tree.root,
        ['address', 'address'],
        multiProof,
      );

      console.log('\nMulti-Proof Verification Results:');
      console.log('Root (from tree):', tree.root);
      console.log('Root (from proof):', proofData.root);
      console.log('Roots match:', tree.root === proofData.root);
      console.log('Number of pairs:', pairs.length);
      console.log('Pairs being verified:');
      for (const pair of pairs) {
        console.log(`  ${pair.token0} <-> ${pair.token1}`);
      }
      console.log('\nInstance verification valid:', isValid);
      console.log('Static verification valid:', staticValid);

      if (isValid && staticValid && tree.root === proofData.root) {
        console.log('\n✓ Multi-proof verification successful!');
      }
      else {
        console.log('\n✗ Multi-proof verification failed!');
        process.exit(1);
      }
    }
    catch (error) {
      console.error('Error verifying multi-proof:', error instanceof Error ? error.message : String(error));
      process.exit(1);
    }
  });

// List command - helpful for viewing all pairs in a tree
program
  .command('list')
  .description('List all token pairs in a Merkle tree')
  .argument('[tree-file]', 'Path to the Merkle tree JSON file', './data/merkle-tree.json')
  .option('--format <format>', 'Output format: table, csv, json', 'table')
  .action(async (treeFile, options) => {
    try {
      // Load tree
      const treeData = JSON.parse(readFileSync(treeFile, 'utf-8'));
      const tree = StandardMerkleTree.load(treeData);

      console.log('Merkle Root:', tree.root);
      console.log('Total pairs:', [...tree.entries()].length);
      console.log('');

      if (options.format === 'csv') {
        console.log('# Token pairs in Merkle tree');
        console.log('# token0,token1');
        for (const [, [token0, token1]] of tree.entries()) {
          console.log(`${token0},${token1}`);
        }
      }
      else if (options.format === 'json') {
        const pairs = [];
        for (const [, [token0, token1]] of tree.entries()) {
          pairs.push({ token0, token1 });
        }
        console.log(JSON.stringify(pairs, null, 2));
      }
      else {
        // Table format
        console.log('Index | Token0                                     | Token1');
        console.log('------|--------------------------------------------|-----------------------------------------');
        for (const [index, [token0, token1]] of tree.entries()) {
          console.log(`${String(index).padEnd(5)} | ${token0} | ${token1}`);
        }
      }
    }
    catch (error) {
      console.error('Error listing pairs:', error instanceof Error ? error.message : String(error));
      process.exit(1);
    }
  });

// Render command - displays visual tree structure
program
  .command('render')
  .description('Display a visual representation of the Merkle tree structure')
  .argument('[tree-file]', 'Path to the Merkle tree JSON file', './data/merkle-tree.json')
  .action(async (treeFile) => {
    try {
      // Load tree
      const treeData = JSON.parse(readFileSync(treeFile, 'utf-8'));
      const tree = StandardMerkleTree.load(treeData);

      console.log('Merkle Tree Visualization');
      console.log('=========================');
      console.log('Root:', tree.root);
      console.log('Total leaves:', [...tree.entries()].length);
      console.log('');

      // Display the tree structure
      console.log(tree.render());
    }
    catch (error) {
      console.error('Error rendering tree:', error instanceof Error ? error.message : String(error));
      process.exit(1);
    }
  });

program.parse();
