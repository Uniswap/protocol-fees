# Merkle Generator CLI

A command-line tool for generating Merkle trees and proofs for the Uniswap V3 Fee Controller. This tool uses the OpenZeppelin Merkle tree library which automatically applies double-hashing to leaves to prevent second preimage attacks, matching the exact format required by the V3FeeAdapter smart contract.

## Installation

```bash
# Install dependencies
pnpm install

# Build the CLI tool
pnpm build

# Optional: link globally
pnpm link --global
```

## Usage

### Input Format - CSV

The CLI accepts token pairs in CSV format. Each row should contain two token addresses separated by a comma:

```csv
# Comments start with # and are ignored
# Format: token0_address, token1_address

# DAI - USDC
0x6B175474E89094C44Da98b954EedeAC495271d0F, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48

# WETH - USDC
0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
```

Features:
- Comments (lines starting with #) are ignored
- Empty lines are skipped
- Whitespace is trimmed
- Addresses can be with or without 0x prefix
- Token order is automatically sorted per Uniswap convention

### Commands

#### 1. Generate Merkle Tree

Generate a Merkle tree from a CSV file containing token pairs.

```bash
merkle-generator generate <input-file> [options]
```

**Options:**
- `-o, --output <file>`: Output file for the Merkle tree (default: `merkle-tree.json`)

**Example:**
```bash
merkle-generator generate examples/token-pairs.csv -o tree.json
```

#### 2. Generate Proof

Generate a Merkle proof for a specific token pair.

```bash
merkle-generator prove <tree-file> <token0> <token1> [options]
```

**Options:**
- `-o, --output <file>`: Output file for the proof

**Example:**
```bash
# Using full addresses
merkle-generator prove tree.json \
  0x6B175474E89094C44Da98b954EedeAC495271d0F \
  0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 \
  -o proof.json

# Without 0x prefix also works
merkle-generator prove tree.json \
  6B175474E89094C44Da98b954EedeAC495271d0F \
  A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
```

The command outputs:
- The merkle root to set in V3FeeAdapter
- The leaf hash (double-hashed)
- The merkle proof array
- Instructions for using the proof on-chain

#### 3. Verify Proof

Verify a previously generated Merkle proof.

```bash
merkle-generator verify <tree-file> <proof-file>
```

**Example:**
```bash
merkle-generator verify tree.json proof.json
```

#### 4. List Token Pairs

List all token pairs in a Merkle tree (useful for verification and debugging).

```bash
merkle-generator list <tree-file> [options]
```

**Options:**
- `--format <format>`: Output format - `table` (default), `csv`, or `json`

**Examples:**
```bash
# Display as table
merkle-generator list tree.json

# Export back to CSV
merkle-generator list tree.json --format csv > pairs-export.csv

# Export as JSON
merkle-generator list tree.json --format json
```

#### 5. Render Tree Structure

Display a visual representation of the Merkle tree structure for debugging and understanding.

```bash
merkle-generator render <tree-file>
```

**Example:**
```bash
merkle-generator render tree.json
```

This command displays:
- The merkle root
- Total number of leaves
- A visual ASCII representation of the tree structure showing how hashes are combined

## Complete Workflow Example

```bash
# 1. Create or edit your CSV file with token pairs
cat > my-pairs.csv << EOF
# My token pairs for fee configuration
0x6B175474E89094C44Da98b954EedeAC495271d0F, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
EOF

# 2. Generate merkle tree
merkle-generator generate my-pairs.csv -o tree.json

# 3. Generate proof for DAI-USDC pair
merkle-generator prove tree.json \
  0x6B175474E89094C44Da98b954EedeAC495271d0F \
  0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 \
  -o proof.json

# 4. Verify the proof
merkle-generator verify tree.json proof.json

# 5. View all pairs in the tree
merkle-generator list tree.json

# 6. Visualize the tree structure
merkle-generator render tree.json
```

## How it Works

### Double-Hashing Format

The tool uses OpenZeppelin's `StandardMerkleTree` which automatically applies double-hashing to leaves. For a token pair `(token0, token1)`, the leaf hash is computed as:

```solidity
bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(token0, token1))));
```

This matches exactly what the V3FeeAdapter expects when verifying proofs.

### Token Ordering

Tokens are automatically sorted according to Uniswap convention (lower address first) to ensure consistency with on-chain pool addresses. You don't need to worry about the order when inputting pairs.

### Integration with V3FeeAdapter

To use the generated proofs with the V3FeeAdapter:

1. **Set the Merkle Root**: The fee setter must call `setMerkleRoot(bytes32 _merkleRoot)` with the generated root

2. **Trigger Fee Update**: Anyone can then call `triggerFeeUpdate()` with the proof:
   ```solidity
   triggerFeeUpdate(
     address token0,    // Lower address
     address token1,    // Higher address
     bytes32[] proof    // Merkle proof from this tool
   )
   ```

## Examples

The `examples/` directory contains sample CSV files:

- `token-pairs.csv` - Basic example with common pairs and comments
- `token-pairs-large.csv` - Extended example with many token pairs

## Automated Proof Generation and Submission

The merkle-generator includes scripts for automated proof generation and submission to the V3FeeAdapter contract. The process is split into two phases for better reliability and resumability:

1. **Generate Proofs** - Pre-generate all merkle proofs and save to files
2. **Submit Proofs** - Submit the pre-generated proofs to the blockchain

This two-phase approach provides several benefits:
- Generate once, submit multiple times if needed
- Resume from any point if interrupted
- Review proofs before submission
- Better error recovery

### Phase 1: Generate Proofs

First, generate all merkle proofs and save them to files:

```bash
# Generate all proofs (saves to ./data/proofs)
pnpm run generate-proofs

# Generate with custom options
pnpm run generate-proofs --batch-size 25 --output-dir ./my-proofs

# Generate limited batches for testing
pnpm run generate-proofs --max-batches 10
```

**Options:**
- `--tree-file <path>`: Path to merkle tree file (default: `./data/merkle-tree.json`)
- `--batch-size <number>`: Number of pairs per batch (default: 50)
- `--output-dir <path>`: Directory to save proof files (default: `./data/proofs`)
- `--max-batches <number>`: Maximum number of batches to generate

**Output:**
- Individual proof files: `proof-batch-0001.json`, `proof-batch-0002.json`, etc.
- Manifest file: `manifest.json` containing metadata about all proofs

### Phase 2: Submit Proofs

After generating proofs, submit them to the blockchain:

```bash
# Configure environment
cp .env.example .env
# Edit .env with:
# - PRIVATE_KEY: Your wallet's private key (needs ETH for gas)
# - RPC_URL: Your RPC endpoint (e.g., Alchemy, Infura)
# - FEE_ADAPTER_ADDRESS: The V3FeeAdapter contract address

# Dry run to test and estimate gas
pnpm run submit-proofs:dry

# Submit all proofs
pnpm run submit-proofs

# Submit with custom options
pnpm run submit-proofs --start-batch 10 --max-batches 5

# Resume from a specific batch (e.g., after interruption)
pnpm run submit-proofs --start-batch 50
```

**Options:**
- `--proofs-dir <path>`: Directory containing proof files (default: `./data/proofs`)
- `--fee-adapter <address>`: V3FeeAdapter contract address (or use env var)
- `--rpc-url <url>`: RPC URL (or use env var)
- `--chain <name>`: Chain name: mainnet, sepolia, optimism, arbitrum, base
- `--dry-run`: Simulate transactions without sending
- `--start-batch <number>`: Start from specific batch number (for resuming)
- `--max-batches <number>`: Maximum number of batches to submit

**Features:**
- **Submission tracking**: Saves progress to `submission-status.json`
- **Automatic resume**: Skip already submitted batches
- **Gas estimation**: Dry run mode estimates gas for each batch
- **Error recovery**: Continue from failed batches
- **Progress reporting**: Shows overall submission status

### Complete Workflow Example

```bash
# Step 1: Generate merkle tree from CSV
merkle-generator generate data/token-pairs.csv -o data/merkle-tree.json

# Step 2: Generate all proofs (9,746 pairs = 195 batches)
pnpm run generate-proofs

# Step 3: Review generated proofs
ls -la data/proofs/
cat data/proofs/manifest.json

# Step 4: Test with dry run (estimate gas)
pnpm run submit-proofs:dry --max-batches 5

# Step 5: Submit proofs to blockchain
pnpm run submit-proofs

# If interrupted, resume from where it stopped
pnpm run submit-proofs --start-batch 100
```

### Legacy All-in-One Script

The original `propagate` script is still available for simpler use cases:

```bash
# All-in-one generation and submission
pnpm run propagate

# Dry run mode
pnpm run propagate:dry
```

This script combines both phases but is less flexible for large-scale operations.

## Development

```bash
# Run in development mode with hot reload
pnpm dev

# Run tests
pnpm test

# Lint code
pnpm lint

# Type check
pnpm typecheck
```

## Common Token Addresses (Ethereum Mainnet)

For reference when creating your CSV files:

| Token | Symbol | Address |
|-------|--------|---------|
| DAI | DAI | `0x6B175474E89094C44Da98b954EedeAC495271d0F` |
| USD Coin | USDC | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` |
| Tether | USDT | `0xdAC17F958D2ee523a2206206994597C13D831ec7` |
| Wrapped Ether | WETH | `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` |
| Wrapped Bitcoin | WBTC | `0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599` |
| Chainlink | LINK | `0x514910771AF9Ca656af840dff83E8264EcF986CA` |
| Uniswap | UNI | `0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984` |
| Frax | FRAX | `0x853d955aCEf822Db058eb8505911ED77F175b99e` |
| stETH | stETH | `0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84` |

## License

MIT
