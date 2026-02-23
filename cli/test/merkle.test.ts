import { StandardMerkleTree } from '@openzeppelin/merkle-tree';
import { describe, expect, it } from 'vitest';

describe('merkle tree operations', () => {
  const testPairs: [string, string][] = [
    ['0x6b175474e89094c44da98b954eedeac495271d0f', '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48'],
    ['0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48', '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'],
    ['0x6b175474e89094c44da98b954eedeac495271d0f', '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'],
    ['0x2260fac5e5542a773aa44fbcfedf7c193bc2c599', '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'],
    ['0x514910771af9ca656af840dff83e8264ecf986ca', '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'],
  ];

  describe('tree generation', () => {
    it('should create a merkle tree with correct root', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);

      expect(tree.root).toBe('0xd24a32a987772cc98d0c01c410c30c37f468f661fa4d2986042b46f59bc7f4ba');
    });

    it('should maintain consistent ordering', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);

      const entries = [...tree.entries()];
      expect(entries).toHaveLength(5);

      // First pair should be DAI-USDC
      expect(entries[0][1]).toEqual(testPairs[0]);
    });

    it('should calculate leaf hashes correctly', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);

      const leafHash = tree.leafHash(testPairs[0]);
      // This is the double-hashed value: keccak256(keccak256(abi.encode(token0, token1)))
      expect(leafHash).toBe('0x9104dda3944cefe37b8192b14eb6b242c03379e064ddba755801f80f02a317ef');
    });

    it('should serialize and deserialize correctly', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);

      const serialized = tree.dump();
      const deserialized = StandardMerkleTree.load(serialized);

      expect(deserialized.root).toBe(tree.root);
      expect([...deserialized.entries()]).toEqual([...tree.entries()]);
    });
  });

  describe('proof generation', () => {
    it('should generate valid proof for existing pair', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);

      const proof = tree.getProof(testPairs[0]);

      expect(proof).toBeDefined();
      expect(proof).toHaveLength(2);
      expect(proof[0]).toBe('0xa60c5e678be668a325aa4020dbb888ec554c30effbe9fee3a04a2cbd886d4d6d');
      expect(proof[1]).toBe('0xe673eab2fe940112218236e9b72e565a0d30093f39a6ac88868eb7a52602132e');
    });

    it('should throw error for non-existent pair', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);

      const nonExistentPair: [string, string] = [
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000001',
      ];

      expect(() => tree.getProof(nonExistentPair)).toThrow();
    });

    it('should generate proof by index', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);

      const proof = tree.getProof(0);

      expect(proof).toBeDefined();
      expect(proof).toHaveLength(2);
    });
  });

  describe('proof verification', () => {
    it('should verify valid proof', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);
      const pair = testPairs[0];
      const proof = tree.getProof(pair);

      const isValid = StandardMerkleTree.verify(
        tree.root,
        ['address', 'address'],
        pair,
        proof,
      );

      expect(isValid).toBe(true);
    });

    it('should reject invalid proof', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);
      const pair = testPairs[0];
      const proof = tree.getProof(pair);

      // Tamper with the proof
      const invalidProof = [...proof];
      invalidProof[0] = '0x0000000000000000000000000000000000000000000000000000000000000000';

      const isValid = StandardMerkleTree.verify(
        tree.root,
        ['address', 'address'],
        pair,
        invalidProof,
      );

      expect(isValid).toBe(false);
    });

    it('should reject proof for wrong pair', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);
      const proof = tree.getProof(testPairs[0]);

      // Try to verify with different pair
      const isValid = StandardMerkleTree.verify(
        tree.root,
        ['address', 'address'],
        testPairs[1],
        proof,
      );

      expect(isValid).toBe(false);
    });

    it('should reject proof with wrong root', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);
      const pair = testPairs[0];
      const proof = tree.getProof(pair);

      const wrongRoot = '0x0000000000000000000000000000000000000000000000000000000000000000';
      const isValid = StandardMerkleTree.verify(
        wrongRoot,
        ['address', 'address'],
        pair,
        proof,
      );

      expect(isValid).toBe(false);
    });
  });

  describe('tree rendering', () => {
    it('should render tree structure', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);

      const rendered = tree.render();

      expect(rendered).toContain('0xd24a32a987772cc98d0c01c410c30c37f468f661fa4d2986042b46f59bc7f4ba');
      expect(rendered).toContain('├─');
      expect(rendered).toContain('└─');
    });
  });

  describe('double hashing', () => {
    it('should apply double hashing as per V3FeeAdapter spec', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);

      // The leaf hash should be keccak256(keccak256(abi.encode(token0, token1)))
      // StandardMerkleTree automatically does this double hashing
      const leafHash = tree.leafHash(testPairs[0]);

      // This is the expected double-hashed value for DAI-USDC pair
      expect(leafHash).toBe('0x9104dda3944cefe37b8192b14eb6b242c03379e064ddba755801f80f02a317ef');
    });
  });

  describe('multi-proof operations', () => {
    it('should generate valid multi-proof for multiple pairs', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);

      // Get multi-proof for first 3 pairs
      const indices = [0, 1, 2];
      const multiProof = tree.getMultiProof(indices);

      expect(multiProof).toBeDefined();
      expect(multiProof.leaves).toHaveLength(3);
      expect(multiProof.proof).toBeDefined();
      expect(multiProof.proofFlags).toBeDefined();

      // Verify that leaves match the expected pairs
      expect(multiProof.leaves).toContainEqual(testPairs[0]);
      expect(multiProof.leaves).toContainEqual(testPairs[1]);
      expect(multiProof.leaves).toContainEqual(testPairs[2]);
    });

    it('should verify valid multi-proof', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);

      const indices = [0, 2, 4];
      const multiProof = tree.getMultiProof(indices);

      // Verify using instance method
      const isValid = tree.verifyMultiProof(multiProof);
      expect(isValid).toBe(true);

      // Verify using static method
      const staticValid = StandardMerkleTree.verifyMultiProof(
        tree.root,
        ['address', 'address'],
        multiProof,
      );
      expect(staticValid).toBe(true);
    });

    it('should reject tampered multi-proof', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);

      const indices = [1, 3];
      const multiProof = tree.getMultiProof(indices);

      // Tamper with proof
      const tamperedProof = {
        ...multiProof,
        proof: [...multiProof.proof],
      };
      if (tamperedProof.proof.length > 0) {
        tamperedProof.proof[0] = '0x0000000000000000000000000000000000000000000000000000000000000000';
      }

      const isValid = tree.verifyMultiProof(tamperedProof);
      expect(isValid).toBe(false);
    });

    it('should handle multi-proof with single pair', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);

      const multiProof = tree.getMultiProof([0]);

      expect(multiProof.leaves).toHaveLength(1);
      expect(tree.verifyMultiProof(multiProof)).toBe(true);
    });

    it('should generate multi-proof by values instead of indices', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);

      // Use actual pairs instead of indices
      const multiProof = tree.getMultiProof([testPairs[0], testPairs[2]]);

      expect(multiProof.leaves).toHaveLength(2);
      expect(tree.verifyMultiProof(multiProof)).toBe(true);
    });

    it('should maintain consistency between single and multi-proofs', () => {
      const tree = StandardMerkleTree.of(testPairs, ['address', 'address']);

      // Generate single proof
      const singleProof = tree.getProof(0);

      // Generate multi-proof for same pair
      const multiProof = tree.getMultiProof([0]);

      // Both should be valid
      expect(StandardMerkleTree.verify(
        tree.root,
        ['address', 'address'],
        testPairs[0],
        singleProof,
      )).toBe(true);

      expect(tree.verifyMultiProof(multiProof)).toBe(true);
    });
  });

  describe('consistency across operations', () => {
    it('should maintain consistency after serialization', () => {
      const tree1 = StandardMerkleTree.of(testPairs, ['address', 'address']);
      const serialized = JSON.stringify(tree1.dump());

      const tree2 = StandardMerkleTree.load(JSON.parse(serialized));

      // Check roots match
      expect(tree2.root).toBe(tree1.root);

      // Check proofs still work
      const proof1 = tree1.getProof(testPairs[0]);
      const proof2 = tree2.getProof(testPairs[0]);
      expect(proof2).toEqual(proof1);

      // Verify both proofs work
      expect(StandardMerkleTree.verify(tree2.root, ['address', 'address'], testPairs[0], proof2)).toBe(true);
    });

    it('should handle duplicate pairs correctly', () => {
      const pairsWithDuplicate = [
        ...testPairs,
        testPairs[0], // Duplicate
      ];

      // StandardMerkleTree should handle duplicates
      const tree = StandardMerkleTree.of(pairsWithDuplicate, ['address', 'address']);

      expect(tree).toBeDefined();
      expect(tree.root).toBeDefined();
    });
  });
});
