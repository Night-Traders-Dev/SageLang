# Sage Blockchain Architecture Guide

This document outlines the modular consensus architecture of the Sage Blockchain library.

## Architectural Overview

The blockchain system has been refactored to decouple the ledger management from the consensus mechanism. The `Blockchain` class now relies on a pluggable `Consensus` provider to handle block validation and block sealing.

## Core Components

### 1. `Consensus` Interface
Located at `lib/blockchain/consensus/base.sage`, this is the base class that all consensus mechanisms must implement:

- `init(blockchain)`: Initializes the provider with the blockchain instance.
- `validate_block(block)`: Validates if a block adheres to the consensus rules.
- `async seal_block(transactions, miner_address)`: Creates and seals a block given the pending transactions.

### 2. Implementations

- **Proof-of-Work (PoW)**: Located at `lib/blockchain/consensus/pow.sage`. It requires miners to perform computational work (mining) to seal a block, based on a configurable difficulty level.
- **Proof-of-Authority (PoA)**: Located at `lib/blockchain/consensus/poa.sage`. Blocks are sealed by an authorized set of nodes without computational mining requirements.

## How to Add a New Consensus Mechanism

To add a new consensus mechanism (e.g., Proof-of-Stake):

1. Create a new file in `lib/blockchain/consensus/`, such as `pos.sage`.
2. Define a class that extends `Consensus`:
   ```sage
   import blockchain.consensus.base as base

   class PoSConsensus(base.Consensus):
       # Implement validate_block and seal_block
   ```
3. Instantiate your provider when creating the `Blockchain`:
   ```sage
   let consensus = pos_mod.PoSConsensus(nil, validator_list)
   let my_coin = bc_mod.Blockchain(consensus, "data/my_chain")
   consensus.blockchain = my_coin
   ```

## Best Practices
- Keep consensus logic modular to ensure it remains testable in isolation.
- Ensure that `validate_block` is strictly deterministic.
- Always use `await` when calling `seal_block` to support asynchronous operations in non-blocking environments.
