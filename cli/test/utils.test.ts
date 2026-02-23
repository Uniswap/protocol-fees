import { describe, expect, it } from 'vitest';
import { formatAddress, isValidAddress, parseCSV, sortTokenPair } from '../src/utils';

describe('utils', () => {
  describe('sortTokenPair', () => {
    it('should sort tokens with lower address first', () => {
      const token0 = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';
      const token1 = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

      const [sorted0, sorted1] = sortTokenPair(token0, token1);

      expect(sorted0).toBe('0x6b175474e89094c44da98b954eedeac495271d0f');
      expect(sorted1).toBe('0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48');
    });

    it('should handle already sorted pairs', () => {
      const token0 = '0x1111111111111111111111111111111111111111';
      const token1 = '0x2222222222222222222222222222222222222222';

      const [sorted0, sorted1] = sortTokenPair(token0, token1);

      expect(sorted0).toBe('0x1111111111111111111111111111111111111111');
      expect(sorted1).toBe('0x2222222222222222222222222222222222222222');
    });

    it('should handle mixed case addresses', () => {
      const token0 = '0xABCDEF1234567890123456789012345678901234';
      const token1 = '0xabcdef1234567890123456789012345678901234';

      const [sorted0, sorted1] = sortTokenPair(token0, token1);

      expect(sorted0).toBe('0xabcdef1234567890123456789012345678901234');
      expect(sorted1).toBe('0xabcdef1234567890123456789012345678901234');
    });
  });

  describe('formatAddress', () => {
    it('should add 0x prefix if missing', () => {
      const address = '6B175474E89094C44Da98b954EedeAC495271d0F';
      expect(formatAddress(address)).toBe('0x6b175474e89094c44da98b954eedeac495271d0f');
    });

    it('should convert to lowercase', () => {
      const address = '0xABCDEF1234567890123456789012345678901234';
      expect(formatAddress(address)).toBe('0xabcdef1234567890123456789012345678901234');
    });

    it('should handle already formatted addresses', () => {
      const address = '0x6b175474e89094c44da98b954eedeac495271d0f';
      expect(formatAddress(address)).toBe('0x6b175474e89094c44da98b954eedeac495271d0f');
    });
  });

  describe('isValidAddress', () => {
    it('should validate correct addresses', () => {
      expect(isValidAddress('0x6B175474E89094C44Da98b954EedeAC495271d0F')).toBe(true);
      expect(isValidAddress('0x0000000000000000000000000000000000000000')).toBe(true);
    });

    it('should reject invalid addresses', () => {
      expect(isValidAddress('0x123')).toBe(false);
      expect(isValidAddress('6B175474E89094C44Da98b954EedeAC495271d0F')).toBe(false);
      expect(isValidAddress('0xGGGG474E89094C44Da98b954EedeAC495271d0F')).toBe(false);
      expect(isValidAddress('not an address')).toBe(false);
    });
  });

  describe('parseCSV', () => {
    it('should parse simple CSV content', () => {
      const csv = `0x1111111111111111111111111111111111111111,0x2222222222222222222222222222222222222222
0x3333333333333333333333333333333333333333,0x4444444444444444444444444444444444444444`;

      const pairs = parseCSV(csv);

      expect(pairs).toHaveLength(2);
      expect(pairs[0]).toEqual(['0x1111111111111111111111111111111111111111', '0x2222222222222222222222222222222222222222']);
      expect(pairs[1]).toEqual(['0x3333333333333333333333333333333333333333', '0x4444444444444444444444444444444444444444']);
    });

    it('should handle comments and empty lines', () => {
      const csv = `# This is a comment
0x1111111111111111111111111111111111111111,0x2222222222222222222222222222222222222222

# Another comment
0x3333333333333333333333333333333333333333,0x4444444444444444444444444444444444444444`;

      const pairs = parseCSV(csv);

      expect(pairs).toHaveLength(2);
    });

    it('should add 0x prefix when missing', () => {
      const csv = `1111111111111111111111111111111111111111,2222222222222222222222222222222222222222`;

      const pairs = parseCSV(csv);

      expect(pairs[0][0]).toBe('0x1111111111111111111111111111111111111111');
      expect(pairs[0][1]).toBe('0x2222222222222222222222222222222222222222');
    });

    it('should sort token pairs', () => {
      const csv = `0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB,0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`;

      const pairs = parseCSV(csv);

      expect(pairs[0][0]).toBe('0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      expect(pairs[0][1]).toBe('0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
    });

    it('should trim whitespace', () => {
      const csv = `  0x1111111111111111111111111111111111111111  ,  0x2222222222222222222222222222222222222222  `;

      const pairs = parseCSV(csv);

      expect(pairs[0]).toEqual(['0x1111111111111111111111111111111111111111', '0x2222222222222222222222222222222222222222']);
    });

    it('should throw error for invalid row length', () => {
      const csv = `0x1111111111111111111111111111111111111111`;

      expect(() => parseCSV(csv)).toThrow('Row 1 must have exactly 2 token addresses');
    });

    it('should throw error for invalid address format', () => {
      const csv = `invalid_address,0x2222222222222222222222222222222222222222`;

      expect(() => parseCSV(csv)).toThrow('Invalid address format in row 1');
    });

    it('should handle real token addresses', () => {
      const csv = `# DAI - USDC
0x6B175474E89094C44Da98b954EedeAC495271d0F, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
# WETH - USDC
0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`;

      const pairs = parseCSV(csv);

      expect(pairs).toHaveLength(2);
      expect(pairs[0][0]).toBe('0x6b175474e89094c44da98b954eedeac495271d0f');
      expect(pairs[0][1]).toBe('0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48');
    });
  });
});
