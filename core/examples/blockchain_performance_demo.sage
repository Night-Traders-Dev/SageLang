# examples/blockchain_performance_demo.sage

import blockchain.blockchain as bc_mod
import blockchain.wallet as wallet_mod
import sys

let db_path = "data/perf_test"
sys.exec("rm -rf " + db_path)

print "Initializing Performance-optimized Blockchain..."
let my_coin = bc_mod.Blockchain(1, db_path)

let alice = wallet_mod.Wallet()
let bob = wallet_mod.Wallet()
let miner = wallet_mod.Wallet()

print "Simulating 50 transactions to test indexing..."
for i in range(50):
    my_coin.add_transaction(alice.address, bob.address, 1)
    if i % 10 == 0:
        my_coin.mine_pending_transactions(miner.address)

my_coin.mine_pending_transactions(miner.address)

print "\nTesting Transaction History Lookup Performance..."
let start = clock()
let history = my_coin.get_transaction_history(alice.address)
let t_end = clock()

print "Found " + str(len(history)) + " transactions for Alice."
print "Lookup time: " + str(t_end - start) + " seconds."

# Verify one transaction
if len(history) > 0:
    print "First Tx Hash: " + history[0]["hash"]
