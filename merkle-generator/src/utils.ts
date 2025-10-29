import { parse } from 'csv-parse/sync';

/**
 * Sort token pairs according to Uniswap convention (lower address first)
 */
export function sortTokenPair(token0: string, token1: string): [string, string] {
  const t0 = token0.toLowerCase();
  const t1 = token1.toLowerCase();
  return t0 < t1 ? [t0, t1] : [t1, t0];
}

/**
 * Parse CSV content into sorted token pairs
 */
export function parseCSV(content: string): [string, string][] {
  const records = parse(content, {
    skip_empty_lines: true,
    skip_records_with_empty_values: true,
    trim: true,
    comment: '#',
  });

  return records.map((row: string[], index: number) => {
    if (row.length !== 2) {
      throw new Error(`Row ${index + 1} must have exactly 2 token addresses, found ${row.length}`);
    }

    let [token0, token1] = row;

    // Add 0x prefix if missing and convert to lowercase
    if (!token0.startsWith('0x'))
      token0 = `0x${token0}`;
    if (!token1.startsWith('0x'))
      token1 = `0x${token1}`;

    // Validate addresses
    if (!/^0x[a-fA-F0-9]{40}$/.test(token0)) {
      throw new Error(`Invalid address format in row ${index + 1}: ${token0}`);
    }
    if (!/^0x[a-fA-F0-9]{40}$/.test(token1)) {
      throw new Error(`Invalid address format in row ${index + 1}: ${token1}`);
    }

    // Sort according to Uniswap convention
    return sortTokenPair(token0, token1);
  });
}

/**
 * Format an address with 0x prefix and lowercase
 */
export function formatAddress(address: string): string {
  let formatted = address;
  if (!formatted.startsWith('0x')) {
    formatted = `0x${formatted}`;
  }
  return formatted.toLowerCase();
}

/**
 * Validate if a string is a valid Ethereum address
 */
export function isValidAddress(address: string): boolean {
  return /^0x[a-fA-F0-9]{40}$/.test(address);
}
