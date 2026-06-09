# Sage Blockchain Library Reference

This guide provides a comprehensive overview of the `lib/blockchain` library, explaining its architecture, module interfaces, and practical usage examples.

## 1. Architectural Overview
The library is designed for modularity and high performance. It features a pluggable consensus architecture, persistent disk-backed storage, and asynchronous transaction processing.

## 2. Core Modules

### 2.1 `Blockchain` (Main Ledger)
The `Blockchain` class is the central orchestrator, managing the chain, mempool, contracts, and node network.

- **Usage:**
  ```sage
  import blockchain.blockchain as bc_mod
  import blockchain.consensus.pow as pow_mod
  
  let consensus = pow_mod.PowConsensus(nil, 2)
  let coin = bc_mod.Blockchain(consensus, "data/my_chain")
  consensus.blockchain = coin
  ```

### 2.2 `Block`
Represents a single block in the chain. Blocks are immutable once mined.

- **Example:**
  ```sage
  import blockchain.block as block_mod
  let block = block_mod.Block(height, tx_list, prev_hash, difficulty)
  await block.mine()
  ```

### 2.3 `Transaction`
Standard value transfer between addresses.

- **Example:**
  ```sage
  import blockchain.transaction as tx_mod
  let tx = tx_mod.Transaction("Alice", "Bob", 100)
  let hash = tx.calculate_hash()
  ```

### 2.4 `Wallet`
Handles address generation and transaction signing.

- **Example:**
  ```sage
  import blockchain.wallet as wallet_mod
  let wallet = wallet_mod.Wallet()
  wallet.sign_transaction(tx)
  ```

### 2.5 `Contract`
Manages SageLang smart contract state and execution.

- **Example:**
  ```sage
  import blockchain.contract as contract_mod
  let c = contract_mod.Contract(source_code)
  let result = c.execute(args, context)
  ```

### 2.6 `LedgerDB`
High-performance storage for the ledger. Uses `blockchain.db`.

- **Example:**
  ```sage
  import blockchain.db as db_mod
  let db = db_mod.LedgerDB("data/ledger")
  await db.save_block(block)
  ```

### 2.7 `Orbit`
Dynamic mining rate model that adjusts based on adoption and supply.

- **Example:**
  ```sage
  import blockchain.orbit as orbit
  let rate = orbit.calculate_mining_rate(users, total_mined, height, score)
  ```

### 2.8 `Staking`
A built-in contract for ORBIT token staking with APR rewards.

- **Example:**
  ```sage
  import blockchain.staking
  let state = {"action": "stake", "value": 1000, "sender": "Alice"}
  let results = staking.execute(state)
  ```

## 3. Consensus Mechanism (Pluggable)
The system supports pluggable consensus via the `Consensus` base class (in `lib/blockchain/consensus/base.sage`).

### Implementations:
- **Proof-of-Work (PoW)**: `PowConsensus` (CPU-bound mining)
- **Proof-of-Authority (PoA)**: `PoAConsensus` (Authorized signers, slashing, rotation)

### Adding Custom Consensus:
1. Extend `Consensus` base class.
2. Implement `validate_block(block)` and `async seal_block(transactions, miner_address)`.
3. Instantiate and inject at `Blockchain` initialization.

## 4. Advanced Features
- **Asynchronous Execution**: Uses `async proc` and `await` for I/O operations (mining, DB writes).
- **Concurrency**: `Blockchain` methods are thread-safe, protected by internal mutexes.
- **Node Scoring**: Tracks miner performance to provide reward multipliers.
- **Authority Rotation**: Dynamic updates to PoA validator sets.
- **Slashing**: Automatic penalties for malicious validators in PoA.
