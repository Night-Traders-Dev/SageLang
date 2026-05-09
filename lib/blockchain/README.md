# Sage Blockchain Library

A pure SageLang implementation of a basic blockchain.

## Modules

- `blockchain.blockchain`: The main `Blockchain` class.
- `blockchain.block`: `Block` class with Proof of Work.
- `blockchain.transaction`: `Transaction` class for value transfers.
- `blockchain.wallet`: `Wallet` class for generating addresses and signing transactions.
- `blockchain.contract`: Smart contract management and execution.
- `blockchain.orbit`: Dynamic mining rate model (Orbit).
- `blockchain.node`: Network node management and scoring.
- `blockchain.db`: High-performance disk-backed ledger database.
- `blockchain.staking`: Smart contract logic for ORBIT staking and rewards.

## Features

- **Terminal CLI**: Fully interactive terminal interface (`examples/blockchain_cli.sage`) for:
    - Wallet creation and management.
    - Transaction history and balance checks.
    - Background mining node operations.
    - Staking interaction.
- **Staking System**: Lock ORBIT for passive rewards:
    - ~5% APR.
    - Claimable in 24h intervals.
    - Automated reward transactions.
- **Async & Non-blocking**: Heavy operations like mining and disk I/O are performed asynchronously using `async proc` and `await`, preventing the main loop from freezing.
- **Thread Safety**: The `Blockchain` class is thread-safe, utilizing internal mutexes to protect the ledger state during concurrent operations.
- **Robust Persistence**: Disk-based storage for blocks, transactions, and state using `blockchain.db`.
- **High-Performance Indexing**:
    - O(1) block lookup by height or hash.
    - O(1) account balance and contract state access.
    - Fast transaction history retrieval using per-address indexing.
- **Orbit Dynamic Mining**: Rewards adjust based on:
    - Early adoption multiplier (User count)
    - Supply tapering (Circulating supply)
    - Time decay (Block height halvings)
    - Node reliability boost (Validator score)
- **Node Scoring**: High-uptime nodes receive up to a 10% boost in mining rewards.
- **Smart Contracts**: Deploy and execute SageLang scripts on-chain using the native VM.
- **Proof of Work**: Configurable difficulty for block mining.
- **Chain Validation**: Integrity checks for hashes and previous links.
- **Mempool**: Transaction buffering before mining.
- **Mining Rewards**: Automated reward transactions for miners.
- **Wallet Support**: Simple address generation and transaction signing.
- **History & Balances**: Query methods for account state.

## Usage Example

```sage
import blockchain.blockchain as bc_mod
import blockchain.wallet as wallet_mod
import blockchain.transaction as tx_mod

let coin = bc_mod.Blockchain(2)
let wallet = wallet_mod.Wallet()

let tx = tx_mod.Transaction(wallet.address, "recipient", 100)
wallet.sign_transaction(tx)
coin.add_signed_transaction(tx)

coin.mine_pending_transactions("miner-address")
print coin.get_balance(wallet.address)
```

## Implementation Notes

- **Hashing**: Uses `crypto.hash.sha256_hex`.
- **Randomness**: Uses `crypto.rand.lcg_create` to ensure compatibility with SageLang's double-precision numbers.
- **Signatures**: Currently uses a simulated signature (hash of transaction + private key).
- **String Slicing**: Requires SageLang version with string slicing support (implemented in `src/c/interpreter.c`).
