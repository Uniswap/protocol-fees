import { describe, expect, it, vi } from 'vitest';
import { checkFees, discoverPools, executeBatchUpdate } from '../src/propagate-fees';

describe('discoverPools', () => {
  it('should extract pool addresses from PoolCreated events', async () => {
    const mockLogs = [
      {
        args: [
          '0x1111111111111111111111111111111111111111',
          '0x2222222222222222222222222222222222222222',
          500n,
          10n,
          '0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        ],
      },
      {
        args: [
          '0x3333333333333333333333333333333333333333',
          '0x4444444444444444444444444444444444444444',
          3000n,
          60n,
          '0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
        ],
      },
    ];

    const mockContract = {
      queryFilter: vi.fn().mockResolvedValue(mockLogs),
      filters: {
        PoolCreated: vi.fn().mockReturnValue('PoolCreated'),
      },
    };

    const mockProvider = {
      getBlockNumber: vi.fn().mockResolvedValue(1000),
    };

    const pools = await discoverPools(
      mockContract as any,
      mockProvider as any,
      0,
      10000,
    );

    expect(pools).toEqual([
      '0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      '0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
    ]);
  });

  it('should chunk requests when block range exceeds chunk size', async () => {
    const mockContract = {
      queryFilter: vi.fn().mockResolvedValue([]),
      filters: {
        PoolCreated: vi.fn().mockReturnValue('PoolCreated'),
      },
    };

    const mockProvider = {
      getBlockNumber: vi.fn().mockResolvedValue(25000),
    };

    await discoverPools(mockContract as any, mockProvider as any, 0, 10000);

    // Should make 3 calls: 0-9999, 10000-19999, 20000-25000
    expect(mockContract.queryFilter).toHaveBeenCalledTimes(3);
  });

  it('should deduplicate pool addresses', async () => {
    const duplicatePool = '0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    const mockLogs = [
      { args: ['0x1', '0x2', 500n, 10n, duplicatePool] },
    ];

    const mockContract = {
      queryFilter: vi
        .fn()
        .mockResolvedValueOnce(mockLogs)
        .mockResolvedValueOnce(mockLogs),
      filters: {
        PoolCreated: vi.fn().mockReturnValue('PoolCreated'),
      },
    };

    const mockProvider = {
      getBlockNumber: vi.fn().mockResolvedValue(15000),
    };

    const pools = await discoverPools(mockContract as any, mockProvider as any, 0, 10000);
    expect(pools).toHaveLength(1);
  });
});

describe('checkFees', () => {
  it('should identify pools needing updates', async () => {
    const pools = [
      '0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      '0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
      '0xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
    ];

    // Pool A: initialized, fee correct (68 = 0x44)
    // Pool B: initialized, fee wrong (0 vs expected 68)
    // Pool C: uninitialized (sqrtPriceX96 = 0)
    const mockSlot0Results = [
      { sqrtPriceX96: 1000n, feeProtocol: 68n }, // correct
      { sqrtPriceX96: 1000n, feeProtocol: 0n }, // wrong
      { sqrtPriceX96: 0n, feeProtocol: 0n }, // uninitialized
    ];

    const mockGetFeeResults = [68, 68, 68];

    const mockPoolContract = {
      slot0: vi.fn(),
    };
    const mockAdapterContract = {
      getFee: vi.fn(),
    };

    for (let i = 0; i < pools.length; i++) {
      mockPoolContract.slot0.mockResolvedValueOnce(mockSlot0Results[i]);
      mockAdapterContract.getFee.mockResolvedValueOnce(mockGetFeeResults[i]);
    }

    const createPoolContract = vi.fn().mockReturnValue(mockPoolContract);

    const result = await checkFees(
      pools,
      mockAdapterContract as any,
      createPoolContract,
    );

    expect(result.initialized).toBe(2);
    expect(result.uninitialized).toBe(1);
    expect(result.correct).toBe(1);
    expect(result.needsUpdate).toEqual(['0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB']);
  });
});

describe('executeBatchUpdate', () => {
  it('should chunk pools into batches and send transactions', async () => {
    const pools = Array.from({ length: 5 }, (_, i) =>
      `0x${String(i).padStart(40, '0')}`);

    const mockReceipt = { hash: '0xabc', gasUsed: 100000n };
    const mockTx = { wait: vi.fn().mockResolvedValue(mockReceipt) };
    const mockAdapterContract = {
      batchTriggerFeeUpdateByPool: vi.fn().mockResolvedValue(mockTx),
    };

    const results = await executeBatchUpdate(
      pools,
      mockAdapterContract as any,
      3,
    );

    expect(results).toHaveLength(2); // 3 + 2
    expect(mockAdapterContract.batchTriggerFeeUpdateByPool).toHaveBeenCalledTimes(2);

    // First batch: 3 pools
    expect(mockAdapterContract.batchTriggerFeeUpdateByPool.mock.calls[0][0]).toHaveLength(3);
    // Second batch: 2 pools
    expect(mockAdapterContract.batchTriggerFeeUpdateByPool.mock.calls[1][0]).toHaveLength(2);
  });

  it('should return empty array when no pools need updates', async () => {
    const mockAdapterContract = {
      batchTriggerFeeUpdateByPool: vi.fn(),
    };

    const results = await executeBatchUpdate([], mockAdapterContract as any, 500);
    expect(results).toHaveLength(0);
    expect(mockAdapterContract.batchTriggerFeeUpdateByPool).not.toHaveBeenCalled();
  });
});
