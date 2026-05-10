# 🌿 SageChain Stack

A complete, working frontier blockchain node and explorer built purely in SageLang.

## Components
1. **`node.sage`**: The P2P network node and miner, utilizing PoS/Orbit consensus, validating blocks, gas metering, and Merkle tree state roots.
2. **`explorer.sage`**: A professional, web-based Block Explorer running on an embedded Sage HTTP server.

## How to Run

Open two terminal windows from the root of the repository.

### Terminal 1: Start the Node
```bash
./sage SageChain/src/node.sage
```

### Terminal 2: Start the Explorer
```bash
./sage SageChain/src/explorer.sage
```

### View
Open your browser and navigate to: [http://localhost:8080](http://localhost:8080)
