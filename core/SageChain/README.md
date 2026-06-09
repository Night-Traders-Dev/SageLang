# 🌿 SageChain Stack

A complete, working enterprise-grade blockchain node and explorer built purely in SageLang.

## Components
1. **`node.sage`**: The P2P network node and miner. It features:
    - **Modular Consensus**: Supports both Proof-of-Work (PoW) and Proof-of-Authority (PoA) with validator slashing.
    - **World State Trie**: Persistent Merkle-Radix Trie for cryptographically proven global account and contract states.
    - **Priority Fee Market**: Dynamic mempool ordering based on gas price.
    - **P2P Sync**: Full node discovery, block broadcasting, and Initial Block Download (IBD).
    - **JSON-RPC 2.0**: A standard HTTP server exposing Ethereum-like endpoints on port 8545.
    - **Smart Contracts & NFTs**: Native VM execution with gas metering, inter-contract transfers, and SNFT-721 support.
    - **HD Wallets**: Deterministic address generation from BIP-39 mnemonic phrases.
2. **`explorer.sage`**: A professional, web-based Block Explorer running on an embedded Sage HTTP server.

## How to Run

Open two terminal windows from the root of the repository.

### Terminal 1: Start the Node
```bash
./sage SageChain/src/node.sage
```
*Note: The node automatically starts the P2P server on port 8333 and the JSON-RPC server on port 8545.*

### Terminal 2: Start the Explorer
```bash
./sage SageChain/src/explorer.sage
```

### View
Open your browser and navigate to: [http://localhost:8080](http://localhost:8080)
