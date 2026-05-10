import blockchain.blockchain as bc
import blockchain.wallet as wallet
import blockchain.net as net
import sys
import io

let db_path = "./sagechain_db"
if not io.exists(db_path):
    print "Initializing new SageChain Database..."

let chain = bc.Blockchain(4, db_path)
let w = wallet.Wallet()

print "================================================="
print "  SageChain Node Started"
print "  Miner Address: " + w.get_address()
print "  Current Block Height: " + str(len(chain.chain))
print "================================================="

# Start a P2P Node on port 8333
let p2p = net.P2PNode(chain, 8333)

async proc run_network():
    print "P2P Network Task Initializing..."
    await p2p.start()

async proc simulator():
    print "Starting network simulator (mining blocks every ~15 seconds)..."
    while true:
        # Simulate network delay using clock()
        let last_check = clock()
        while clock() - last_check < 15.0:
            # Do actual work or just wait
            let i = 0
            while i < 1000:
                i = i + 1 # Internal loop to reduce clock() calls
            
        print "Mining new block..."
        let blk = await chain.mine_pending_transactions(w.get_address())
        
        # Create some random transactions
        let tx = chain.add_transaction(w.get_address(), "0x" + str(clock()), 1.5)
        w.sign_transaction(tx)
        chain.add_signed_transaction(tx)
        
        await p2p.broadcast("new_block", blk.to_dict())

# Use the scheduler to run both async tasks
await run_network()
await simulator()

