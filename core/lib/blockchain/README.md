# Sage Blockchain Library

A pure SageLang implementation of an enterprise-grade L1 blockchain.

## Modules

- `blockchain.blockchain`: The main `Blockchain` class managing state, memory pool, and chain consensus.
- `blockchain.block`: `Block` class representing the ledger components.
- `blockchain.transaction`: `Transaction` class for value transfers and smart contract calls.
- `blockchain.wallet`: `Wallet` class for generating addresses and signing transactions, supporting HD derivation (BIP-39 style).
- `blockchain.contract`: Smart contract management and execution via the native VM.
- `blockchain.orbit`: Dynamic mining rate model (Orbit).
- `blockchain.node`: Network node management and scoring.
- `blockchain.db`: High-performance disk-backed ledger database.
- `blockchain.staking`: Smart contract logic for ORBIT staking and rewards.
- `blockchain.consensus.*`: Pluggable consensus mechanisms (`pow`, `poa`).
- `blockchain.merkle`: World State Trie and Merkle tree implementations.
- `blockchain.rpc`: JSON-RPC 2.0 API Server.
- `blockchain.net`: P2P networking layer with IBD and block broadcasting.
- `blockchain.events`: Contract event emission and logging.
- `blockchain.std.nft`: SNFT-721 Standard for Non-Fungible Tokens.

## Features

- **Modular Consensus**: Pluggable architecture supporting both **Proof-of-Work (PoW)** and **Proof-of-Authority (PoA)** with automatic validator slashing for equivocation.
- **World State Trie**: Persistent Merkle-Radix Trie for global account balances and contract state, cryptographically proven via `state_root`.
- **JSON-RPC 2.0 API**: Standard HTTP server exposing Ethereum-like endpoints (`eth_getBalance`, `eth_sendRawTransaction`, `eth_blockNumber`).
- **P2P Synchronization**: Full node discovery, block broadcasting, Initial Block Download (IBD), and Longest Chain fork resolution.
- **Priority Fee Market**: Mempool prioritization based on `gas_price`, dynamically compensating miners.
- **Smart Contracts & NFTs**: Native VM execution with gas metering, inter-contract transfers, and a complete SNFT-721 Non-Fungible Token standard.
- **HD Wallets**: Deterministic address generation from 12-word mnemonic phrases (BIP-39 simulation).
- **Terminal CLI**: Fully interactive terminal interface (`examples/blockchain_cli.sage`) for wallet creation, transfers, and background mining.
- **Staking System**: Lock ORBIT for passive rewards (~5% APR, 24h intervals) via system smart contracts.
- **Robust Persistence**: Disk-based storage for blocks, transactions, and state using `blockchain.db`.
- **Orbit Dynamic Mining**: Rewards adjust dynamically based on early adoption, supply tapering, and node reliability.

## Usage Example

```sage
import blockchain.blockchain as bc_mod
import blockchain.wallet as wallet_mod
import blockchain.consensus.pow as pow_mod
import blockchain.transaction as tx_mod

let consensus = pow_mod.PowConsensus(nil, 2)
let coin = bc_mod.Blockchain(consensus, "./sagechain_db")
consensus.blockchain = coin

let wallet = wallet_mod.Wallet(nil)

let tx = coin.add_transaction(wallet.get_address(), "recipient", 100)
wallet.sign_transaction(tx)
coin.add_signed_transaction(tx)

coin.mine_pending_transactions("miner-address")
print coin.get_balance(wallet.get_address())
```

## Implementation Notes

- **Hashing**: Uses native high-performance `sha256`.
- **Signatures**: Uses a simulated signature (hash of transaction + private key) unless `libsage_crypto.so` (Ed25519) is available via FFI.
- **Execution**: The chain is fully synchronous but optimized for O(1) reads via `blockchain.db`.
