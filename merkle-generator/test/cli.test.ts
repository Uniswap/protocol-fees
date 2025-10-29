import { execSync } from 'node:child_process';
import { existsSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { StandardMerkleTree } from '@openzeppelin/merkle-tree';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

describe('cLI integration tests', () => {
  const cliPath = join(process.cwd(), 'dist', 'cli.js');
  const testDir = join(process.cwd(), 'test');
  const testCSV = join(testDir, 'test-pairs.csv');
  const testTree = join(testDir, 'test-tree.json');
  const testProof = join(testDir, 'test-proof.json');

  const csvContent = `# Test token pairs
0x6B175474E89094C44Da98b954EedeAC495271d0F, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
0x6B175474E89094C44Da98b954EedeAC495271d0F, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`;

  beforeEach(() => {
    // Create test CSV file
    writeFileSync(testCSV, csvContent);
  });

  afterEach(() => {
    // Clean up test files
    [testCSV, testTree, testProof].forEach((file) => {
      if (existsSync(file)) {
        unlinkSync(file);
      }
    });
  });

  function runCommand(command: string): string {
    try {
      return execSync(`node ${cliPath} ${command}`, {
        encoding: 'utf-8',
        cwd: process.cwd(),
      });
    }
    catch (error: any) {
      throw new Error(`Command failed: ${error.message}\nOutput: ${error.stdout}\nError: ${error.stderr}`);
    }
  }

  describe('generate command', () => {
    it('should generate merkle tree from CSV', () => {
      const output = runCommand(`generate ${testCSV} -o ${testTree}`);

      expect(output).toContain('Merkle tree generated successfully!');
      expect(output).toContain('Total pairs: 3');
      expect(existsSync(testTree)).toBe(true);

      // Verify tree structure
      const treeData = JSON.parse(readFileSync(testTree, 'utf-8'));
      const tree = StandardMerkleTree.load(treeData);

      expect(tree.root).toBeDefined();
      expect([...tree.entries()]).toHaveLength(3);
    });

    it('should handle CSV with comments and empty lines', () => {
      const csvWithComments = `# Comment line
# Another comment
0x1111111111111111111111111111111111111111, 0x2222222222222222222222222222222222222222

# Middle comment
0x3333333333333333333333333333333333333333, 0x4444444444444444444444444444444444444444
`;
      writeFileSync(testCSV, csvWithComments);

      const output = runCommand(`generate ${testCSV} -o ${testTree}`);

      expect(output).toContain('Total pairs: 2');
      expect(existsSync(testTree)).toBe(true);
    });

    it('should sort token pairs automatically', () => {
      const unsortedCSV = `0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB, 0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`;
      writeFileSync(testCSV, unsortedCSV);

      runCommand(`generate ${testCSV} -o ${testTree}`);

      const treeData = JSON.parse(readFileSync(testTree, 'utf-8'));
      const tree = StandardMerkleTree.load(treeData);
      const [[, pair]] = tree.entries();

      expect(pair[0]).toBe('0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      expect(pair[1]).toBe('0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
    });
  });

  describe('prove command', () => {
    beforeEach(() => {
      // Generate a tree first
      runCommand(`generate ${testCSV} -o ${testTree}`);
    });

    it('should generate multi-proof for single pair', () => {
      const output = runCommand(
        `prove ${testTree} "0x6B175474E89094C44Da98b954EedeAC495271d0F,0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48" -o ${testProof}`,
      );

      expect(output).toContain('Multi-proof generated successfully!');
      expect(output).toContain('Multi-proof valid: true');
      expect(existsSync(testProof)).toBe(true);

      // Verify proof structure
      const proofData = JSON.parse(readFileSync(testProof, 'utf-8'));
      expect(proofData.root).toBeDefined();
      expect(proofData.pairs).toBeDefined();
      expect(proofData.pairs).toHaveLength(1);
      expect(proofData.multiProof).toBeDefined();
      expect(proofData.multiProof.proof).toBeInstanceOf(Array);
      expect(proofData.multiProof.proofFlags).toBeInstanceOf(Array);
      expect(proofData.valid).toBe(true);
    });

    it('should handle addresses without 0x prefix', () => {
      const output = runCommand(
        `prove ${testTree} "6B175474E89094C44Da98b954EedeAC495271d0F,A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48" -o ${testProof}`,
      );

      expect(output).toContain('Multi-proof generated successfully!');
      expect(existsSync(testProof)).toBe(true);
    });

    it('should handle tokens in any order', () => {
      // Provide tokens in reverse order
      const output = runCommand(
        `prove ${testTree} "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,0x6B175474E89094C44Da98b954EedeAC495271d0F" -o ${testProof}`,
      );

      expect(output).toContain('Multi-proof generated successfully!');

      const proofData = JSON.parse(readFileSync(testProof, 'utf-8'));
      // Should be sorted correctly
      expect(proofData.pairs[0].token0).toBe('0x6b175474e89094c44da98b954eedeac495271d0f');
      expect(proofData.pairs[0].token1).toBe('0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48');
    });

    it('should generate multi-proof for multiple pairs from CSV', () => {
      // Create a CSV with multiple pairs
      const multiPairsCSV = join(testDir, 'multi-pairs.csv');
      writeFileSync(multiPairsCSV, `# Multiple pairs to prove
0x6B175474E89094C44Da98b954EedeAC495271d0F, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`);

      const output = runCommand(
        `prove ${testTree} ${multiPairsCSV} -o ${testProof}`,
      );

      expect(output).toContain('Multi-proof generated successfully!');
      expect(output).toContain('Number of pairs in proof: 2');

      const proofData = JSON.parse(readFileSync(testProof, 'utf-8'));
      expect(proofData.pairs).toHaveLength(2);

      // Clean up
      unlinkSync(multiPairsCSV);
    });
  });

  describe('verify command', () => {
    beforeEach(() => {
      // Generate tree and proof
      runCommand(`generate ${testCSV} -o ${testTree}`);
      runCommand(
        `prove ${testTree} "0x6B175474E89094C44Da98b954EedeAC495271d0F,0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48" -o ${testProof}`,
      );
    });

    it('should verify valid multi-proof', () => {
      const output = runCommand(`verify ${testTree} ${testProof}`);

      expect(output).toContain('Multi-proof verification successful!');
      expect(output).toContain('Instance verification valid: true');
      expect(output).toContain('Static verification valid: true');
      expect(output).toContain('Roots match: true');
    });

    it('should reject invalid multi-proof', () => {
      // Tamper with the proof
      const proofData = JSON.parse(readFileSync(testProof, 'utf-8'));
      if (proofData.multiProof.proof.length > 0) {
        proofData.multiProof.proof[0] = '0x0000000000000000000000000000000000000000000000000000000000000000';
      }
      writeFileSync(testProof, JSON.stringify(proofData));

      expect(() => runCommand(`verify ${testTree} ${testProof}`)).toThrow();
    });

    it('should verify multi-proof with multiple pairs', () => {
      // Create a CSV with multiple pairs to prove
      const multiPairsCSV = join(testDir, 'multi-pairs-verify.csv');
      writeFileSync(multiPairsCSV, `0x6B175474E89094C44Da98b954EedeAC495271d0F, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
0x6B175474E89094C44Da98b954EedeAC495271d0F, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`);

      runCommand(`prove ${testTree} ${multiPairsCSV} -o ${testProof}`);
      const output = runCommand(`verify ${testTree} ${testProof}`);

      expect(output).toContain('Number of pairs: 2');
      expect(output).toContain('Multi-proof verification successful!');

      // Clean up
      unlinkSync(multiPairsCSV);
    });
  });

  describe('list command', () => {
    beforeEach(() => {
      runCommand(`generate ${testCSV} -o ${testTree}`);
    });

    it('should list pairs in table format', () => {
      const output = runCommand(`list ${testTree}`);

      expect(output).toContain('Total pairs: 3');
      expect(output).toContain('Token0');
      expect(output).toContain('Token1');
      expect(output).toContain('0x6b175474e89094c44da98b954eedeac495271d0f');
    });

    it('should export as CSV', () => {
      const output = runCommand(`list ${testTree} --format csv`);

      expect(output).toContain('# Token pairs in Merkle tree');
      expect(output).toContain('0x6b175474e89094c44da98b954eedeac495271d0f,0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48');

      // Should be valid CSV
      const lines = output.split('\n').filter(l => l && !l.startsWith('#'));
      expect(lines.length).toBeGreaterThanOrEqual(3);
    });

    it('should export as JSON', () => {
      const output = runCommand(`list ${testTree} --format json`);

      const pairs = JSON.parse(output.split('\n').slice(3).join('\n')); // Skip header lines
      expect(pairs).toBeInstanceOf(Array);
      expect(pairs).toHaveLength(3);
      expect(pairs[0]).toHaveProperty('token0');
      expect(pairs[0]).toHaveProperty('token1');
    });
  });

  describe('render command', () => {
    beforeEach(() => {
      runCommand(`generate ${testCSV} -o ${testTree}`);
    });

    it('should render tree visualization', () => {
      const output = runCommand(`render ${testTree}`);

      expect(output).toContain('Merkle Tree Visualization');
      expect(output).toContain('Root:');
      expect(output).toContain('Total leaves: 3');
      expect(output).toContain('├─');
      expect(output).toContain('└─');
    });
  });

  describe('error handling', () => {
    it('should handle non-existent input file', () => {
      expect(() => runCommand('generate non-existent.csv')).toThrow();
    });

    it('should handle invalid CSV format', () => {
      writeFileSync(testCSV, 'invalid,csv,with,too,many,columns');
      expect(() => runCommand(`generate ${testCSV} -o ${testTree}`)).toThrow();
    });

    it('should handle invalid address format', () => {
      writeFileSync(testCSV, 'not-an-address, 0x1111111111111111111111111111111111111111');
      expect(() => runCommand(`generate ${testCSV} -o ${testTree}`)).toThrow();
    });

    it('should handle non-existent pair in prove command', () => {
      runCommand(`generate ${testCSV} -o ${testTree}`);

      expect(() => runCommand(
        `prove ${testTree} "0x0000000000000000000000000000000000000000,0x0000000000000000000000000000000000000001" -o ${testProof}`,
      )).toThrow();
    });
  });
});
